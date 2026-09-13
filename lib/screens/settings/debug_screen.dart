import 'package:g1_extended/models/g1/calendar.dart';
import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/dashboard_panel.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/models/g1/notification.dart';
import 'package:g1_extended/models/g1/text.dart';
import 'package:g1_extended/utils/glasses_text.dart';
import 'package:g1_extended/models/g1/translate.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/glasses_event_log.dart';
import 'package:g1_extended/services/lens_emulator.dart';
import 'package:g1_extended/widgets/lens_panel.dart';
import 'package:g1_extended/utils/bitmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:g1_extended/services/notification_apps.dart';

import 'package:g1_extended/services/navigation_capture.dart';


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

  void _copyNavigationCapture() async {
    final capture = NavigationCapture.singleton;
    // The recording happens in whichever isolate receives notifications —
    // not this one. The file is the bridge.
    await capture.ensureLoaded();
    if (capture.isEmpty) {
      _toast('Nothing captured yet. Start navigating first, then come back.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: capture.export()));
    _toast('${capture.length} notifications copied as JSON.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sends one page with an explicit status byte.
  ///
  /// The three candidates differ only in that byte, so sending the same
  /// sentence three times and watching the lens is the whole experiment.
  void _sendTextWithStatus(int screenStatus) async {
    final String text = _textController.text;
    if (text.isEmpty) {
      _showInfoSnackBar('Please enter some text to send');
      return;
    }
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    final packet = TextMessage(
      GlassesText.prepare(text),
    ).constructPageWithStatus(screenStatus: screenStatus);
    await bluetoothManager.sendCommandToGlasses(packet);
    _showInfoSnackBar(
      'Sent with status 0x${screenStatus.toRadixString(16).toUpperCase()}',
    );
  }

  /// Writes one news card into the dashboard's second pane.
  ///
  /// Never seen on real glasses: this is the first thing to try when a pair
  /// is available, and the mirror above says what left the phone either way.
  void _sendDashboardNews() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    final text = _textController.text.isEmpty
        ? 'Le volet accepte enfin notre contenu.'
        : _textController.text;
    final packets = DashboardNews.write(
      mode: DashboardMode.dual,
      slot: 1,
      card: NewsCard(source: 'G1 Extended', text: text),
    );

    for (final packet in packets) {
      await bluetoothManager.sendCommandToGlasses(packet);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _showInfoSnackBar('News slot 1, ${packets.length} paquet(s)');
  }

  /// Sends the calibration chart to the map pane, then the cursor.
  void _sendDashboardMap() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    const mode = DashboardMode.dual;
    final packets = DashboardMap.image(
      mode: mode,
      packed: DashboardMap.testPattern(mode),
    );

    for (final packet in packets) {
      await bluetoothManager.sendCommandToGlasses(packet);
      await Future.delayed(const Duration(milliseconds: 30));
    }

    await bluetoothManager.sendCommandToGlasses(
      DashboardMap.cursor(
        mode: mode,
        x: DashboardMap.widthFor(mode) ~/ 2,
        y: DashboardMap.height ~/ 2,
        packed: DashboardMap.cursorSprite(),
        syncId: DashboardPanel.firstSyncId + packets.length,
      ),
    );
    _showInfoSnackBar('Carte envoyée, ${packets.length} paquets');
  }

  /// Sends the same paragraph wrapped at a given width.
  ///
  /// Twenty is what the app inherited, twenty-five is what the
  /// teleprompter's paginator says was measured on these glasses, forty is
  /// what two other implementations compute from the pixel column. Only a
  /// lens can say which one fills the panel without spilling off it.
  void _sendTextAtWidth(int width) async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }

    const sample =
        'La liaison tient sur les deux branches, la batterie affiche '
        'quatre-vingt-quatre pour cent, et le prochain rendez-vous est a '
        'quinze heures trente.';
    final text = _textController.text.isEmpty ? sample : _textController.text;

    final packets = TextMessage(
      GlassesText.prepare(text),
      charactersPerLine: width,
    ).constructSendText();

    for (final packet in packets) {
      await bluetoothManager.sendCommandToGlasses(packet);
      await Future.delayed(const Duration(milliseconds: 60));
    }
    _showInfoSnackBar('$width caractères par ligne, ${packets.length} paquets');
  }

  /// Tries the command that should take the banner off the lens.
  ///
  /// Never seen working: if the lens clears, the app gains a way to stop
  /// showing a notification instead of waiting for it to time out.
  void _clearNotification() async {
    if (!bluetoothManager.isConnected) {
      _showInfoSnackBar('Glasses are not connected');
      return;
    }
    // Both temples, for the same reason 0x4B goes to both.
    await bluetoothManager.sendCommandToGlasses([Commands.CLEAR_NOTIFICATION]);
    _showInfoSnackBar('0x4C envoyé aux deux branches');
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

    // Under our own identity, freshly allowlisted. The button used to send
    // as "chat.fluffy.fluffychat" — an app that had never posted a real
    // notification here, so it was never in the allowlist the glasses
    // filter on, and the firmware discarded the send without a trace. The
    // button could not work, and its silence read as the whole pipeline
    // being broken. Upstream has the same flaw; real notifications working
    // there is why nobody noticed.
    final self = (await PackageInfo.fromPlatform()).packageName;
    await NotificationApps.singleton.remember(self, 'G1 Extended');
    await bluetoothManager.sendSetup();
    await Future.delayed(const Duration(milliseconds: 500));

    await bluetoothManager.sendNotification(
      NCSNotification(
        msgId: 1234567890,
        appIdentifier: self,
        title: "Hello",
        subtitle: "subtitle",
        message: message,
        displayName: "DEV",
      ),
    );
    _showInfoSnackBar('Sent as $self, allowlist refreshed first');
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
          // What the lens is showing, rebuilt from the bytes that were
          // actually written to it. Everything below this line sends
          // something; this is where you see what it did.
          const Text(
            'Lentille (576x136, 1 bit)',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          StreamBuilder<LensState>(
            stream: LensEmulator.mirror.changes,
            initialData: LensEmulator.mirror.state,
            builder: (context, snapshot) {
              return LensPanel(
                state: snapshot.data ?? const LensState(),
              );
            },
          ),
          const SizedBox(height: 20),
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
              OutlinedButton(
                onPressed: _clearNotification,
                child: const Text('0x4C'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // How wide a line really is, settled by looking rather than by
          // reading: the app inherited twenty, the teleprompter's paginator
          // says twenty-five was measured here, two other implementations
          // compute forty from the 488 pixel column.
          const Text(
            'Largeur de ligne, à départager sur les lunettes',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: () => _sendTextAtWidth(20),
                child: const Text('20'),
              ),
              OutlinedButton(
                onPressed: () => _sendTextAtWidth(25),
                child: const Text('25'),
              ),
              OutlinedButton(
                onPressed: () => _sendTextAtWidth(40),
                child: const Text('40 actuel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The status byte is the open question on the text command: this
          // app sends 0x30, two other implementations compose 0x31, and the
          // plain-text mode is 0x71. Same sentence, three bytes, one lens.
          const Text(
            'Octet de statut, à comparer sur les lunettes',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: () => _sendTextWithStatus(TextMessage.statusToday),
                child: const Text('0x30 actuel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _sendTextWithStatus(TextMessage.statusAiNewContent),
                child: const Text('0x31'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _sendTextWithStatus(TextMessage.statusTextShow),
                child: const Text('0x71'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // What the glasses reported on their own. Four sub-codes are acted
          // on; the others are named here and nowhere else.
          Row(
            children: [
              const Text(
                'Événements des lunettes',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(GlassesEventLog.instance.clear),
                child: const Text('Vider'),
              ),
            ],
          ),
          StreamBuilder<List<GlassesEvent>>(
            stream: GlassesEventLog.instance.changes,
            initialData: GlassesEventLog.instance.events,
            builder: (context, snapshot) {
              final events = snapshot.data ?? const <GlassesEvent>[];
              if (events.isEmpty) {
                return const Text(
                  'Rien reçu depuis le lancement.',
                  style: TextStyle(fontSize: 12),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in events.take(12))
                    Text(
                      '${event.at.hour.toString().padLeft(2, '0')}:'
                      '${event.at.minute.toString().padLeft(2, '0')}:'
                      '${event.at.second.toString().padLeft(2, '0')}  '
                      '${event.side}  ${event.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: event.isUnnamed
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // The dashboard's second pane, which nothing in this app has ever
          // written to. Dual mode: the pane is 376 wide there rather than
          // 296, so put the dashboard in dual before trying it.
          const Text(
            'Volet du dashboard (mode dual), jamais testé sur lunettes',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: _sendDashboardNews,
                child: const Text('News'),
              ),
              OutlinedButton(
                onPressed: _sendDashboardMap,
                child: const Text('Carte test'),
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
          // The instrument for "it does not detect the Maps instructions":
          // drive a junction or two with navigation running, come back here,
          // copy, and paste it into a bug report. The capture holds the raw
          // notification fields and nothing else.
          ElevatedButton(
            onPressed: _copyNavigationCapture,
            child: const Text("Copy navigation capture"),
          ),

        ],
      ),
    );
  }
}
