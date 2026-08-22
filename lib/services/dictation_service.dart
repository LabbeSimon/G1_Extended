import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';

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
  Future<void> record(
    String text, {
    DictationSource source = DictationSource.glasses,
    bool showOnGlasses = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      debugPrint('DictationService: empty transcript, ignoring');
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
