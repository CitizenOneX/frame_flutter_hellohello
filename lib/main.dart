import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frame_flutter_hellohello/bluetooth.dart';
import 'package:logging/logging.dart';

void main() => runApp(const MainApp());

/// basic State Machine for the app; mostly for bluetooth lifecycle,
/// all app activity expected to take place during "running" state
enum ApplicationState {
  disconnected,
  scanning,
  connecting,
  ready,
  running,
}

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  late ApplicationState _currentState;
  int _helloCounter = 0;

  // Use BrilliantBluetooth for communications with Frame
  BrilliantDevice? _connectedDevice;
  StreamSubscription? _scanStream;
  StreamSubscription<BrilliantDevice>? _deviceStateSubs;

  // to show a debug log message box on the screen
  final _statusLog = <String>[];
  final ScrollController _logScrollController = ScrollController();

  MainAppState() {
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
    _currentState = ApplicationState.disconnected;
    setUpInstructions();
  }

  void _appendLog(String line) {
    _log.fine(line);
    _statusLog.add(line);
    if (_logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    if (mounted) setState(() {});
  }

  void setUpInstructions() {
    _appendLog('Instructions (for a Hello, World?!)');
    _appendLog('Make sure Frame has already been paired in this phone\'s bluetooth settings. Setting up Noa on this device is the recommended way to do this.');
    _appendLog('');
    _appendLog('If Noa is running in the background when you tap, then you should see the usual "tap me in" prompt or the "no wireless connection" icon on Frame. Click "Connect Frame" before the Frame goes back to sleep.');
    _appendLog('If Noa\'s main.lua isn\'t running then you might see the word "FRAME".');
    _appendLog('');
    _appendLog('Either case should work fine. Click "Connect Frame" to connect.');
    _appendLog('Click "Say Hello!" to send a Hello to the Frame and receive a Hello back from the Frame in this log.');
    _appendLog('');
    _appendLog('When finished, click "Finish" to send a Reset signal to the Frame so it restarts the Noa main.lua script and will go to sleep after a short period of no activity.');
    _appendLog('---------------------------------------------------------------');
    _appendLog('Ready: Tap Frame once to wake then click "Connect Frame".');
  }

  Future<void> _scanForFrame() async {
    _currentState = ApplicationState.scanning;
    if (mounted) setState(() {});

    await BrilliantBluetooth.requestPermission();

    await _scanStream?.cancel();
    _scanStream = BrilliantBluetooth.scan()
      .timeout(const Duration(seconds: 5), onTimeout: (sink) {
        // Scan timeouts can occur without having found a Frame, but also
        // after the Frame is found and being connected to, even though
        // the first step after finding the Frame is to stop the scan.
        // In those cases we don't want to change the application state back
        // to disconnected
        switch (_currentState) {
          case ApplicationState.scanning:
            _appendLog('Scan timed out after 5 seconds');
            _currentState = ApplicationState.disconnected;
            if (mounted) setState(() {});
            break;
          case ApplicationState.connecting:
            // found a device and started connecting, just let it play out
            break;
          case ApplicationState.ready:
          case ApplicationState.running:
            // already connected, nothing to do
            break;
          default:
            _appendLog('Unexpected state on scan timeout: $_currentState');
            if (mounted) setState(() {});
        }
      })
      .listen((device) {
        _appendLog('Frame found, connecting');
        _currentState = ApplicationState.connecting;
        if (mounted) setState(() {});

        _connectToScannedFrame(device);
      });
  }

  Future<void> _connectToScannedFrame(BrilliantScannedDevice device) async {
    try {
      _appendLog('connecting to scanned device: $device');
      _connectedDevice = await BrilliantBluetooth.connect(device);
      _appendLog('device connected: ${_connectedDevice!.device.remoteId}');

      // subscribe to connection state for the device to detect disconnections
      // so we can transition the app to a disconnected state
      await _deviceStateSubs?.cancel();
      _deviceStateSubs = _connectedDevice!.connectionState.listen((bd) {
        _appendLog('Frame connection state change: ${bd.state.name}');
        if (bd.state == BrilliantConnectionState.disconnected) {
          _currentState = ApplicationState.disconnected;
          _appendLog('Frame disconnected: currentState: $_currentState');
          if (mounted) setState(() {});
        }
      });

      try {
        // terminate the main.lua (if currently running) so we can run our lua code
        // TODO looks like if the signal comes too early after connection, it isn't registered
        Future.delayed(const Duration(milliseconds: 500));
        await _connectedDevice!.sendBreakSignal();

        // Application is ready to go!
        _currentState = ApplicationState.ready;
        if (mounted) setState(() {});

      } catch (e) {
        _currentState = ApplicationState.disconnected;
        _appendLog('Error while sending break signal: $e');
        if (mounted) setState(() {});

        _disconnectFrame();
      }
    } catch (e) {
      _currentState = ApplicationState.disconnected;
      _appendLog('Error while connecting and/or discovering services: $e');
    }
  }

  Future<void> _reconnectFrame() async {
    if (_connectedDevice != null) {
      try {
        _appendLog('connecting to existing device: $_connectedDevice');
        await BrilliantBluetooth.reconnect(_connectedDevice!.uuid);
        _appendLog('device connected: $_connectedDevice');

        // subscribe to connection state for the device to detect disconnections
        // and transition the app to a disconnected state
        await _deviceStateSubs?.cancel();
        _deviceStateSubs = _connectedDevice!.connectionState.listen((bd) {
          _appendLog('Frame connection state change: ${bd.state.name}');
          if (bd.state == BrilliantConnectionState.disconnected) {
            _currentState = ApplicationState.disconnected;
            _appendLog('Frame disconnected');
            if (mounted) setState(() {});
          }
        });

        try {
          // terminate the main.lua (if currently running) so we can run our lua code
          // TODO looks like if the signal comes too early after connection, it isn't registered
          Future.delayed(const Duration(milliseconds: 500));
          await _connectedDevice!.sendBreakSignal();

          // Application is ready to go!
          _currentState = ApplicationState.ready;
          if (mounted) setState(() {});

        } catch (e) {
          _currentState = ApplicationState.disconnected;
          _appendLog('Error while sending break signal: $e');
          if (mounted) setState(() {});

        _disconnectFrame();
        }
      } catch (e) {
        _currentState = ApplicationState.disconnected;
        _appendLog('Error while connecting and/or discovering services: $e');
        if (mounted) setState(() {});
      }
    }
    else {
      _currentState = ApplicationState.disconnected;
      _appendLog('Current device is null, reconnection not possible');
      if (mounted) setState(() {});
    }
  }

  Future<void> _disconnectFrame() async {
    if (_connectedDevice != null) {
      try {
        _appendLog('Disconnecting from Frame');
        // break first in case it's sleeping - otherwise the reset won't work
        await _connectedDevice!.sendBreakSignal();
        _appendLog('Break signal sent');
        // TODO the break signal needs some more time to be processed before we can reliably send the reset signal, by the looks of it
        await Future.delayed(const Duration(milliseconds: 500));

        // try to reset device back to running main.lua
        await _connectedDevice!.sendResetSignal();
        _appendLog('Reset signal sent');
        // TODO the reset signal doesn't seem to be processed in time if we disconnect immediately, so we introduce a delay here to give it more time
        // The sdk's sendResetSignal actually already adds 100ms delay
        // perhaps it's not quite enough.
        await Future.delayed(const Duration(milliseconds: 500));

      } catch (e) {
          _appendLog('Error while sending reset signal: $e');
      }

      try{
          // try to disconnect cleanly if the device allows
          await _connectedDevice!.disconnect();
      } catch (e) {
          _appendLog('Error while calling disconnect(): $e');
      }
    }
    else {
      _appendLog('Current device is null, disconnection not possible');
    }

    _currentState = ApplicationState.disconnected;
    if (mounted) setState(() {});
  }

  /// The rx/tx messaging for this app is very simple, just display a Hello on the Frame for a few seconds,
  /// and get the Frame to send a Hello back to the host.
  Future<void> _runApplication() async {
    _currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // send a lua command to display the message on the Frame
      _appendLog('Host sending: "Hello, Frame!"');
      var colors = ['WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN', 'BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'];
      await _connectedDevice!.sendString('frame.display.text("${++_helloCounter}. Hello, Frame! {batt:" .. frame.battery_level() .. "%}", 50, 100, {color="${colors[_helloCounter%15]}"}) frame.display.show()', awaitResponse: false);

      // TODO sometimes the text won't display, adding some delay here to give it time to execute before executing the reply code (although I thought the calls were supposed to queue)
      await Future.delayed(const Duration(milliseconds: 500));

      // send some lua code to evaluate on the frame and return a string back to the Host
      String? response = await _connectedDevice!.sendString('print("$_helloCounter. Hello, Host! {fw:" .. frame.FIRMWARE_VERSION .. "}")', awaitResponse: true);
      _appendLog('Frame says: "$response"');

      // leave the Hello message visible for 5 seconds
      await Future.delayed(const Duration(seconds: 5));

      // clear the display (note: frame.display.clear() has been removed, and frame.display.show() without
      // and preceding draw commands doesn't seem to clear the display.
      // Even an empty string doesn't, but a single space does.)
      await _connectedDevice!.sendString('frame.display.text(" ", 50, 100) frame.display.show()', awaitResponse: false);
      // TODO sometimes the text won't clear, adding some delay here to give it time to execute (although I thought the calls were supposed to queue)
      await Future.delayed(const Duration(milliseconds: 500));


      // Ideally, we would put the Frame into light sleep which would clear the display, still listen for
      // bluetooth messages (maybe even just a wakeup message), and shut down the camera to conserve power,
      // so for this app that would work well.
      // at present there is only frame.sleep(seconds) which needs to be interrupted with a break signal
      // but it doesn't clear the display, and frame.sleep() which goes into a deep sleep and
      // terminates the bluetooth connection, requiring reconnection and service discovery etc.
      // the break signal approach would not work well if the user application has its own lua scripts running
      // in loops on the Frame, but it would be okay here since we're just sending fragments

    } catch (e) {
      _appendLog('Error executing application logic: $e');
    }

    _currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // work out the states of the footer buttons based on the app state
    List<Widget> pfb = [];

    switch (_currentState) {
      case ApplicationState.disconnected:
        pfb.add(TextButton(onPressed: _connectedDevice != null ? _reconnectFrame : _scanForFrame, child: const Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Say Hello!')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;

      case ApplicationState.scanning:
      case ApplicationState.connecting:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Say Hello!')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;

      case ApplicationState.ready:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(TextButton(onPressed: _runApplication, child: const Text('Say Hello!')));
        pfb.add(TextButton(onPressed: _disconnectFrame, child: const Text('Finish')));
        break;

      case ApplicationState.running:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Say Hello!')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;
    }

    return MaterialApp(
      title: 'Hello Hello',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Frame Flutter 'Hello, Hello!'"),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: _statusLog.length,
                    itemBuilder: (context, index) {
                      return Text(_statusLog[index]);
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ]
            ),
          )
        ),
        persistentFooterButtons: pfb,
      ),
    );
  }
}
