import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/home_assistant_service.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/services/voice_command_runner.dart';
import 'package:g1_extended/services/voice_commands.dart';

/// A single piece of dictated text, kept on the device.
class Dictation {
  final String text;
  final DateTime capturedAt;
  final DictationSource source;

  /// The stored audio this text came from, when there is one.
  ///
  /// Text is a lossy summary of what was said — a name misheard, a word
  /// the model did not know. Keeping the link means the recording can
  /// always be played back and settled by ear.
  final String? recordingId;

  const Dictation({
    required this.text,
    required this.capturedAt,
    required this.source,
    this.recordingId,
  });

  bool get hasAudio => recordingId != null;

  Map<String, dynamic> toMap() => {
        'text': text,
        'capturedAt': capturedAt.toIso8601String(),
        'source': source.name,
        if (recordingId != null) 'recordingId': recordingId,
      };

  static Dictation fromMap(Map map) => Dictation(
        text: map['text'] as String? ?? '',
        capturedAt:
            DateTime.tryParse(map['capturedAt'] as String? ?? '') ??
                DateTime.now(),
        source: DictationSource.values.firstWhere(
          (s) => s.name == map['source'],
          orElse: () => DictationSource.glasses,
        ),
        recordingId: map['recordingId'] as String?,
      );
}

enum DictationSource { glasses, phone }

/// Receives recognised speech and does the two useful things with it:
/// shows it on the glasses so the wearer can confirm what was heard, and
/// keeps it in a local history they can read back on the phone.
///
/// This is where the AI assistant used to sit. Everything now stays on device.
class DictationService {
  DictationService._internal();
  static final DictationService singleton = DictationService._internal();
  factory DictationService() => singleton;

  static const String _boxName = 'dictations';
  static const int _maxEntries = 200;

  final StreamController<Dictation> _controller =
      StreamController<Dictation>.broadcast();

  /// Emits every new dictation as it is captured.
  Stream<Dictation> get stream => _controller.stream;

  /// Handles a finished transcript: display it, then remember it.
  ///
  /// When an assistant endpoint is configured, the transcript is a question
  /// rather than a note, and the answer is what reaches the lens.
  Future<void> record(
    String text, {
    DictationSource source = DictationSource.glasses,
    bool showOnGlasses = true,
    bool saveAsNote = false,
    String? recordingId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      debugPrint('DictationService: empty transcript, ignoring');
      return;
    }

    // The right temple dictates a note, and a note is content, not
    // conversation: no command parsing, no assistant. Someone dictating
    // "call the plumber tomorrow" into their shopping list wants those
    // words kept, not a phone call placed.
    if (saveAsNote) {
      await _saveAsNote(trimmed, source, recordingId);
      return;
    }

    // Anything the phone can do itself is done here rather than sent to a
    // model: it is faster, works without a network, and replying to a message
    // is not something a model could do at all.
    final command = VoiceCommands.parse(trimmed);
    if (command != null && await _isActionable(command)) {
      await _runCommand(command);
      return;
    }

    if (await AssistantService.singleton.isConfigured()) {
      await _askAssistant(trimmed, source);
      return;
    }

    // Home Assistant's conversation agent is a general assistant, not a
    // switch panel: with an LLM behind it, it answers a question as readily
    // as it turns off a lamp. Reaching it only through the imperative
    // triggers above — "allume", "turn off", "is the" — threw that away.
    // Every actual question fell straight past it to be shown as plain
    // text, which is exactly what "the assistant does nothing" looks like
    // from the outside when a house is the only thing configured.
    if (await HomeAssistantService.singleton.isConfigured()) {
      await _askHouse(trimmed, source);
      return;
    }

    final entry = Dictation(
      text: trimmed,
      capturedAt: DateTime.now(),
      source: source,
      recordingId: recordingId,
    );

    if (showOnGlasses) {
      try {
        await BluetoothManager.singleton.sendPriorityText(trimmed);
      } catch (e) {
        debugPrint('DictationService: could not display on glasses: $e');
      }
    }

    await _persist(entry);
    if (!_controller.isClosed) _controller.add(entry);
  }

  Future<void> _saveAsNote(
    String text,
    DictationSource source, [
    String? recordingId,
  ]) async {
    final note = await NotesLibrary.singleton.create(
      title: 'Note',
      body: text,
      // A slot if one is going spare; never at the cost of evicting
      // something already pinned.
      pinIfPossible: true,
    );

    // Confirmation on the lens, saying where it went. "Noted" alone would
    // leave the wearer unsure whether it reached the glasses' slots or only
    // the phone — which decides whether they can call it back up later.
    final where = note.pinnedSlot != null
        ? 'Noted · slot ${note.pinnedSlot}'
        : 'Noted · on the phone';
    try {
      await BluetoothManager.singleton.sendPriorityText('$where\n$text');
    } catch (e) {
      debugPrint('DictationService: could not confirm the note: $e');
    }

    await _persist(Dictation(
      text: text,
      capturedAt: DateTime.now(),
      source: source,
      recordingId: recordingId,
    ));
  }

  /// Whether a recognised command can actually be carried out.
  ///
  /// "Turn off the hall light" looks like a house command whether or not a
  /// house is connected. When one is not, the phrase is better treated as
  /// an ordinary question — the assistant may well know what to say about
  /// it — than answered with a setup instruction nobody asked for.
  Future<bool> _isActionable(VoiceCommandMatch command) async {
    if (command.kind != VoiceCommandKind.house) return true;
    return HomeAssistantService.singleton.isConfigured();
  }

  Future<void> _runCommand(VoiceCommandMatch command) async {
    final outcome = await VoiceCommandRunner.singleton.run(command);
    if (outcome.isEmpty) return;

    try {
      await BluetoothManager.singleton.sendPriorityText(outcome);
    } catch (e) {
      debugPrint('DictationService: could not show the outcome: $e');
    }

    await _persist(Dictation(
      text: outcome,
      capturedAt: DateTime.now(),
      source: DictationSource.glasses,
    ));
  }

  /// Sends the transcript on and shows the answer.
  ///
  /// The question goes up on the lens first: a local model can take several
  /// seconds, and a display that stays blank looks like the touchpad did not
  /// register the press.
  Future<void> _askAssistant(String question, DictationSource source) =>
      _askAndShow(question, source, () async {
        final result = await AssistantService.singleton.ask(question);
        return switch (result) {
          AssistantAnswer(:final text) => text,
          AssistantFailure(:final reason) => reason,
        };
      });

  Future<void> _askHouse(String question, DictationSource source) =>
      _askAndShow(question, source, () async {
        final result = await HomeAssistantService.singleton.converse(question);
        return switch (result) {
          HaOk(:final text) => text,
          HaFailure(:final reason) => reason,
        };
      });

  /// Shows the question on the lens, waits for [answer], shows the reply.
  ///
  /// Shared by both assistants: which one is asked changes where the
  /// sentence goes, not what the wearer sees happen. The failure text is
  /// displayed like an answer on purpose — "The token was refused" on the
  /// lens is how someone finds out their setup is wrong, where a silent
  /// return leaves them tapping the temple again.
  Future<void> _askAndShow(
    String question,
    DictationSource source,
    Future<String> Function() answer,
  ) async {
    final bluetooth = BluetoothManager.singleton;

    try {
      await bluetooth.sendPriorityText('$question\n…');
    } catch (e) {
      debugPrint('DictationService: could not echo the question: $e');
    }

    final text = await answer();

    try {
      await bluetooth.sendPriorityText(text);
    } catch (e) {
      debugPrint('DictationService: could not display the answer: $e');
    }

    await _persist(Dictation(
      text: '$question\n$text',
      capturedAt: DateTime.now(),
      source: source,
    ));
  }

  /// Most recent dictations first.
  Future<List<Dictation>> history() async {
    final box = await _openBox();
    return box.values
        .whereType<Map>()
        .map(Dictation.fromMap)
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  Future<void> clearHistory() async {
    final box = await _openBox();
    await box.clear();
  }

  Future<void> _persist(Dictation entry) async {
    final box = await _openBox();
    await box.add(entry.toMap());

    // Keep the box bounded so a chatty user never fills the device.
    while (box.length > _maxEntries) {
      await box.deleteAt(0);
    }
  }

  Future<Box> _openBox() async =>
      Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : await Hive.openBox(_boxName);
}
