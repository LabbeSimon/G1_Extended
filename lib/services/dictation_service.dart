import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/services/voice_command_runner.dart';
import 'package:g1_extended/services/voice_commands.dart';

/// A single piece of dictated text, kept on the device.
class Dictation {
  final String text;
  final DateTime capturedAt;
  final DictationSource source;

  const Dictation({
    required this.text,
    required this.capturedAt,
    required this.source,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'capturedAt': capturedAt.toIso8601String(),
        'source': source.name,
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
      await _saveAsNote(trimmed, source);
      return;
    }

    // Anything the phone can do itself is done here rather than sent to a
    // model: it is faster, works without a network, and replying to a message
    // is not something a model could do at all.
    final command = VoiceCommands.parse(trimmed);
    if (command != null) {
      await _runCommand(command);
      return;
    }

    if (await AssistantService.singleton.isConfigured()) {
      await _askAssistant(trimmed);
      return;
    }

    final entry = Dictation(
      text: trimmed,
      capturedAt: DateTime.now(),
      source: source,
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

  Future<void> _saveAsNote(String text, DictationSource source) async {
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
    ));
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
  Future<void> _askAssistant(String question) async {
    final bluetooth = BluetoothManager.singleton;

    try {
      await bluetooth.sendPriorityText('$question\n…');
    } catch (e) {
      debugPrint('DictationService: could not echo the question: $e');
    }

    final result = await AssistantService.singleton.ask(question);
    final text = switch (result) {
      AssistantAnswer(:final text) => text,
      AssistantFailure(:final reason) => reason,
    };

    try {
      await bluetooth.sendPriorityText(text);
    } catch (e) {
      debugPrint('DictationService: could not display the answer: $e');
    }

    await _persist(Dictation(
      text: '$question\n$text',
      capturedAt: DateTime.now(),
      source: DictationSource.glasses,
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
