import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/even_ai_screen.dart';
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

  /// Where the touchpad's choice of microphone is kept.
  static const String glassesMicrophoneKey = 'use_glasses_microphone';

  /// Whether the touchpad dictates through the glasses microphone.
  ///
  /// The default, because that path records first and transcribes once the
  /// touchpad is released, on the phone, with the offline model: what was
  /// said exists before anything can go wrong with the text, as with Even AI
  /// in the official app. The phone microphone is the other choice —
  /// Android's own recogniser, live, with nothing recorded.
  static Future<bool> usesGlassesMicrophone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(glassesMicrophoneKey) ?? true;
  }
  static const int _maxEntries = 200;

  final StreamController<Dictation> _controller =
      StreamController<Dictation>.broadcast();

  /// Bumped on every lens message, so a scheduled clear only fires if nothing
  /// newer has been shown since.
  int _displayToken = 0;

  /// Emits every new dictation as it is captured.
  Stream<Dictation> get stream => _controller.stream;

  /// Handles a finished transcript: display it, then remember it.
  ///
  /// When an assistant is configured, the transcript is a question
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
      await _show(trimmed);
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
    await _show('$where\n$text');

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

    await _show(outcome);

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
  /// Shows [text] on the lens and, unless told otherwise, closes it once
  /// there has been time to read it.
  ///
  /// The glasses hold whatever was last sent until something ends it: left
  /// alone, an answer or a confirmation stays on the lens for good. Clearing
  /// the text was not enough either — the AI screen the long press opened
  /// stayed up, empty, with its scroll bar. The official app ends the session
  /// with status 0 (its exitAI) a few seconds after the answer; this does the
  /// same, timed to how much there is to read.
  Future<void> _show(String text, {bool clearAfter = true}) async {
    final bluetooth = BluetoothManager.singleton;
    final token = ++_displayToken;
    try {
      await bluetooth.sendPriorityText(text);
    } catch (e) {
      debugPrint('DictationService: could not display on glasses: $e');
      return;
    }
    if (!clearAfter) return;

    final seconds = (text.length / 8).clamp(8, 20).round();
    Future.delayed(Duration(seconds: seconds), () async {
      // A newer message took the lens in the meantime: leave it be.
      if (token != _displayToken) return;
      try {
        if (!await EvenAiScreen.singleton.close()) {
          // No AI session to end, or a firmware that refused it: exit to
          // the dashboard, as the official app does when its session hangs.
          await bluetooth.sendCommandToGlasses(ClearScreen.buildCommand());
        }
      } catch (e) {
        debugPrint('DictationService: could not close the lens: $e');
      }
    });
  }

  Future<void> _askAndShow(
    String question,
    DictationSource source,
    Future<String> Function() answer,
  ) async {
    // The question stays up while the answer is fetched; the answer replaces
    // it and is what gets cleared.
    await _show('$question\n…', clearAfter: false);

    final text = await answer();
    await _show(text);

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
