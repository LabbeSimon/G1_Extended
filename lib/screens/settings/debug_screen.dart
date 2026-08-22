import 'package:g1_extended/models/g1/calendar.dart';
import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/models/g1/notification.dart';
import 'package:g1_extended/models/g1/translate.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/utils/bitmap.dart';
import 'package:flutter/material.dart';

import 'package:g1_extended/screens/settings/battery_capture_screen.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageSate();
}

class _DebugPageSate extends State<DebugPage> {
  final TextEditingController _textController = TextEditingController();
  final BluetoothManager bluetoothManager = BluetoothManager();

  void _showInfoSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _sendText() async {
    final String text = _textController.text;
    if (text.isEmpty) {
      _showInfoSnackBar('Please enter some text to send');
      return;
    }

    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    await bluetoothManager.sendText(text);
  }

  void _sendNotification() async {
    final String message = _textController.text;
    if (message.isEmpty) {
      _showInfoSnackBar('Please enter a message to send');
      return;
    }

    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    await bluetoothManager.sendNotification(
      NCSNotification(
        msgId: 1234567890,
        appIdentifier: "chat.fluffy.fluffychat",
        title: "Hello",
        subtitle: "subtitle",
        message: message,
        displayName: "DEV",
      ),
    );
  }

  void _sendImage() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    final image = await generateDemoBMP();
    await bluetoothManager.sendBitmap(image);
  }

  void _testCalendar() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    await bluetoothManager.setDashboardLayout(DashboardLayout.DASHBOARD_FULL);
    await bluetoothManager.sendCommandToGlasses(
      CalendarItem(
        location: "Test Place",
        name: "Test Event",
        time: "12:00",
      ).constructDashboardCalendarItem(),
    );
  }

  void _sendNoteDemo() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    final note1 = Note(
      noteNumber: 1,
      name: 'G1 Extended',
      text:
          '☐ 09:00 Take medication\n☐ 09:18 Take bus 85\n☐ 09:58 take train to FN',
    );
    final note2 = Note(
      noteNumber: 2,
      name: 'Note 2',
      text: 'This is another note',
    );

    await bluetoothManager.sendNote(note1);
    await bluetoothManager.sendNote(note2);
    await bluetoothManager.setDashboardLayout(DashboardLayout.DASHBOARD_DUAL);
  }

  // Removed _debugTimeCommand as it relied on TimeAndWeather

  void _debugTranslateCommand() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    final tr = Translate(
      fromLanguage: TranslateLanguages.FRENCH,
      toLanguage: TranslateLanguages.ENGLISH,
    );
    await bluetoothManager.sendCommandToGlasses(tr.buildSetupCommand());
    await bluetoothManager.rightGlass!.sendData(
      tr.buildRightGlassStartCommand(),
    );
    for (final cmd in tr.buildInitalScreenLoad()) {
      await bluetoothManager.sendCommandToGlasses(cmd);
    }
    await Future.delayed(const Duration(milliseconds: 200));
    await bluetoothManager.setMicrophone(true);

    final demoText = [
      "Hello and welcome to G1 Extended",
      "These glasses cured my autism!",
      "haha no just kidding but they are amazing",
      "you are watching a demo of translation",
      "but nobody is talking??",
      "that is why I said DEMO...",
      "anyway enjoy G1 Extended",
      "and don't forget to like and subscribe",
    ];
    final demoTextFrench = [
      "Bonjour et bienvenue sur G1 Extended",
      "Ces lunettes ont guéri mon autisme!",
      "haha non je rigole mais elles sont incroyables",
      "vous regardez une démo de traduction",
      "mais personne ne parle??",
      "c'est pourquoi j'ai dit DEMO...",
      "de toute façon, profitez de G1 Extended",
      "et n'oubliez pas de liker et de vous abonner",
    ];
    for (var i = 0; i < demoText.length; i++) {
      await bluetoothManager.sendCommandToGlasses(
        tr.buildTranslatedCommand(demoText[i]),
      );
      await bluetoothManager.sendCommandToGlasses(
        tr.buildOriginalCommand(demoTextFrench[i]),
      );
      await Future.delayed(const Duration(seconds: 4));
    }
    await bluetoothManager.setMicrophone(false);
  }


  @override
  void initState() {
    super.initState();
    // Optionally initiate scan here or via button
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _textController,
            decoration: const InputDecoration(labelText: 'Enter text to send'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _sendText,
                child: const Text('Send Text'),
              ),
              ElevatedButton(
                onPressed: _sendNotification,
                child: const Text('Send Notification'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sendImage,
            child: const Text("Send Image"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sendNoteDemo,
            child: const Text("Send Note Demo"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _testCalendar,
            child: const Text("Test Calendar"),
          ),
          const SizedBox(height: 20),
          // Removed button for Debug Time/Weather Command
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _debugTranslateCommand,
            child: const Text("Debug Translate"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BatteryCaptureScreen(),
              ),
            ),
            child: const Text("Battery frame capture"),
          ),
        ],
      ),
    );
  }
}
