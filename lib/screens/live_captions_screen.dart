import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:g1_extended/models/g1/translate.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/utils/lc3.dart';

/// Live captions: what the glasses microphone hears, written on the glasses
/// display as it is spoken. Recognition runs entirely on the device.
class LiveCaptionsScreen extends StatefulWidget {
  const LiveCaptionsScreen({super.key});

  @override
  State<LiveCaptionsScreen> createState() => _LiveCaptionsScreenState();
}

class _LiveCaptionsScreenState extends State<LiveCaptionsScreen> {
  /// The glasses caption area holds roughly this many characters.
  static const int _maxGlassesChars = 220;

  /// How often buffered audio is drained and fed to the recogniser.
  static const Duration _drainInterval = Duration(milliseconds: 200);

  final BluetoothManager _bluetooth = BluetoothManager();

  Timer? _drainTimer;
  LiveTranscription? _session;
  StreamSubscription<String>? _textSubscription;
  Translate? _display;

  bool _isRunning = false;
  String _caption = '';

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    if (_isRunning) return;

    if (!_bluetooth.isConnected) {
      _notify('Glasses are not connected');
      return;
    }

    try {
      _session = await SpeechRecognitionService.singleton.startLiveTranscription();
    } on SpeechModelMissingException catch (e) {
      _notify(e.toString());
      return;
    }

    // Put the glasses into their two-line caption layout.
    final display = Translate(
      fromLanguage: TranslateLanguages.FRENCH,
      toLanguage: TranslateLanguages.ENGLISH,
    );
    _display = display;

    await _bluetooth.sendCommandToGlasses(display.buildSetupCommand());
    await _bluetooth.rightGlass?.sendData(display.buildRightGlassStartCommand());
    for (final command in display.buildInitalScreenLoad()) {
      await _bluetooth.sendCommandToGlasses(command);
    }
    await Future.delayed(const Duration(milliseconds: 200));
    await _bluetooth.setMicrophone(true);

    final receiver = BluetoothReciever();
    receiver.voiceCollector.reset();
    receiver.voiceCollector.isRecording = true;

    _textSubscription = _session!.text.listen(_onCaption);

    _drainTimer = Timer.periodic(_drainInterval, (_) async {
      final encoded = await receiver.voiceCollector.getAllDataAndReset();
      if (encoded.isEmpty) return;
      final pcm = await LC3.decodeLC3(Uint8List.fromList(encoded));
      if (pcm.isNotEmpty) await _session?.feed(pcm);
    });

    setState(() => _isRunning = true);
  }

  Future<void> _onCaption(String text) async {
    final line = text.length > _maxGlassesChars
        ? text.substring(text.length - _maxGlassesChars)
        : text;

    if (mounted) setState(() => _caption = line);

    final display = _display;
    if (display == null) return;
    await _bluetooth.sendCommandToGlasses(display.buildOriginalCommand(line));
  }

  Future<void> _stop() async {
    await _teardown();
    if (mounted) setState(() => _isRunning = false);
  }

  Future<void> _teardown() async {
    _drainTimer?.cancel();
    _drainTimer = null;

    await _textSubscription?.cancel();
    _textSubscription = null;

    await _session?.close();
    _session = null;
    _display = null;

    final receiver = BluetoothReciever();
    receiver.voiceCollector.isRecording = false;
    receiver.voiceCollector.reset();

    await _bluetooth.setMicrophone(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live captions')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _isRunning ? _stop : _start,
              icon: Icon(_isRunning ? Icons.stop : Icons.mic),
              label: Text(_isRunning ? 'Stop' : 'Start'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _caption.isEmpty
                      ? 'Nothing heard yet.'
                      : _caption,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
