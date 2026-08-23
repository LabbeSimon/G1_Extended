import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:g1_extended/models/g1/translate.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/memory_state.dart';
import 'package:g1_extended/services/translation_service.dart';
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

  // Live translation of what is being said.
  bool _translate = false;
  String _from = 'en';
  String _to = 'fr';
  bool _modelsReady = false;
  bool _downloading = false;
  String _translated = '';
  Timer? _translateDebounce;

  /// The firmware's own language ids, for the caption layout's header. It
  /// knows only these four; anything else falls back to English — cosmetic
  /// only, the text lines carry the actual languages.
  static int _firmwareLanguage(String code) => switch (code) {
        'zh' => TranslateLanguages.CHINESE,
        'nl' => TranslateLanguages.DUTCH,
        'fr' => TranslateLanguages.FRENCH,
        _ => TranslateLanguages.ENGLISH,
      };

  @override
  void initState() {
    super.initState();
    _loadTranslationState();
  }

  /// Asks whether there is room before handing the speech model to a
  /// native loader that cannot fail politely.
  ///
  /// Pressing Start used to end the process outright — nothing thrown,
  /// nothing logged, the app gone and the glasses' link with it. That
  /// cannot be caught afterwards, so it is asked about beforehand; and
  /// since a refusal here is a guess, it is offered as a warning the
  /// wearer may override rather than a rule.
  Future<bool> _memoryAllows() async {
    final memory = await MemoryState.read();
    // No answer is not a warning.
    if (memory == null || !memory.speechModelIsRisky) return true;
    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Not much memory free'),
        content: Text(
          'Captions load a speech model of some tens of megabytes, and the '
          'part of Android that loads it cannot fail gracefully — if there '
          'is not enough room the app is closed outright, taking the '
          'glasses connection with it.\n\n'
          '${memory.summary}.\n\n'
          'Closing a few other apps first is the reliable fix. You can also '
          'go ahead anyway.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Go ahead'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _loadTranslationState() async {
    final (from, to) = await TranslationService.singleton.pair();
    final ready = await TranslationService.singleton.modelsReady();
    if (!mounted) return;
    setState(() {
      _from = from;
      _to = to;
      _modelsReady = ready;
    });
  }

  Future<void> _setPair(String from, String to) async {
    await TranslationService.singleton.setPair(from, to);
    await _loadTranslationState();
  }

  Future<void> _downloadModels() async {
    setState(() => _downloading = true);
    final ok = await TranslationService.singleton.downloadModels();
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _modelsReady = ok;
    });
    if (!ok) _notify('The model download failed.');
  }

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

    if (!await _memoryAllows()) return;

    try {
      _session = await SpeechRecognitionService.singleton.startLiveTranscription();
    } on SpeechModelMissingException catch (e) {
      _notify(e.toString());
      return;
    }

    // Put the glasses into their two-line caption layout, headed with the
    // configured pair when translating.
    final display = Translate(
      fromLanguage: _firmwareLanguage(_translate ? _from : _to),
      toLanguage: _firmwareLanguage(_to),
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
    // The original goes up immediately, translated or not: a caption that
    // waits for its translation reads as the microphone cutting out.
    await _bluetooth.sendCommandToGlasses(display.buildOriginalCommand(line));

    if (!_translate || !_modelsReady) return;

    // Translating every partial would thrash the engine mid-word. A short
    // debounce means the line is translated when it pauses — which is also
    // roughly when a listener's eyes drop to the second line.
    _translateDebounce?.cancel();
    _translateDebounce = Timer(const Duration(milliseconds: 600), () async {
      final translated = await TranslationService.singleton.translate(line);
      if (translated == null) return;
      if (mounted) setState(() => _translated = translated);

      final still = _display;
      if (still == null) return;
      await _bluetooth
          .sendCommandToGlasses(still.buildTranslatedCommand(translated));
    });
  }

  Future<void> _stop() async {
    await _teardown();
    if (mounted) setState(() => _isRunning = false);
  }

  Future<void> _teardown() async {
    _translateDebounce?.cancel();
    _translateDebounce = null;
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

  Widget _languageDropdown({required bool isFrom}) {
    final value = isFrom ? _from : _to;
    return DropdownButtonFormField<String>(
      initialValue:
          TranslationService.languages.containsKey(value) ? value : 'en',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isFrom ? 'They speak' : 'You read',
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final entry in TranslationService.languages.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _isRunning
          ? null
          : (code) {
              if (code == null) return;
              _setPair(isFrom ? code : _from, isFrom ? _to : code);
            },
    );
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
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _translate,
              // The pair changes while stopped; mid-session the glasses'
              // layout is already headed with the old one.
              onChanged: _isRunning
                  ? null
                  : (value) => setState(() => _translate = value),
              title: const Text('Translate what is said'),
              subtitle: Text(_translate && !_modelsReady
                  ? 'The language models are not on the device yet.'
                  : 'On the device, once its models are downloaded. The '
                      'lens shows both lines.'),
            ),
            if (_translate) ...[
              Row(
                children: [
                  Expanded(child: _languageDropdown(isFrom: true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16),
                  ),
                  Expanded(child: _languageDropdown(isFrom: false)),
                ],
              ),
              if (!_modelsReady)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.tonal(
                    onPressed: _downloading ? null : _downloadModels,
                    child: Text(_downloading
                        ? 'Downloading…'
                        : 'Download the two models (~30 MB each, once)'),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _caption.isEmpty ? 'Nothing heard yet.' : _caption,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (_translate && _translated.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _translated,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
