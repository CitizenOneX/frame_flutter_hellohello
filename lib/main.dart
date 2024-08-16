import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'simple_frame_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  int _helloCounter = 0;

  // to show a debug log message box on the screen
  final _statusLog = <String>[];
  final ScrollController _logScrollController = ScrollController();

  MainAppState() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
      _appendLog('${record.level.name}: ${record.time}: ${record.message}');
    });

    setUpInstructions();
  }

  void _appendLog(String line) {
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
    _appendLog('Either case should work fine. Click "Connect" to connect, then "Start".');
    _appendLog('Click the Message Icon to send a Hello to the Frame and receive a Hello back from the Frame in this log.');
    _appendLog('');
    _appendLog('When finished, click "Stop", then "Disconnect" to send a Reset signal to the Frame so it restarts the Noa main.lua script and will go to sleep after a short period of no activity.');
    _appendLog('---------------------------------------------------------------');
    _appendLog('Ready: Tap Frame once to wake then click "Connect".');
  }

  /// send a simple message to the frame display
  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // send a lua command to display the message on the Frame
      _log.fine('Host sending: "Hello, Frame!"');
      var colors = ['WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN', 'BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'];
      await frame!.sendString('frame.display.text("${++_helloCounter}. Hello, Frame! {batt:" .. frame.battery_level() .. "%}", 50, 100, {color="${colors[_helloCounter%15]}"}) frame.display.show()', awaitResponse: false);

      // TODO sometimes the text won't display, adding some delay here to give it time to execute before executing the reply code (although I thought the calls were supposed to queue)
      await Future.delayed(const Duration(milliseconds: 500));

      // send some lua code to evaluate on the frame and return a string back to the Host
      String? response = await frame!.sendString('print("$_helloCounter. Hello, Host! {fw:" .. frame.FIRMWARE_VERSION .. "}")', awaitResponse: true);
      _log.fine('Frame says: "$response"');

      // leave the Hello message visible for 5 seconds
      await Future.delayed(const Duration(seconds: 5));

      // clear the display (note: frame.display.clear() has been removed, and frame.display.show() without
      // and preceding draw commands doesn't seem to clear the display.
      // Even an empty string doesn't, but a single space does.)
      await frame!.sendString('frame.display.text(" ", 50, 100) frame.display.show()', awaitResponse: false);
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
      _log.fine('Error executing application logic: $e');
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hello Hello!',
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
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.message_outlined), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
