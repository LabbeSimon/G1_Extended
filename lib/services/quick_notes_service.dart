import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';

/// One of the four note slots the glasses keep on device.
class QuickNote {
  final int slot;
  final String title;
  final String body;

  const QuickNote({
    required this.slot,
    required this.title,
    required this.body,
  });

  bool get isEmpty => title.isEmpty && body.isEmpty;

  Map<String, dynamic> toMap() => {'title': title, 'body': body};
}

/// Owns the four quick note slots and keeps the glasses in step with them.
///
/// The phone is the record of truth. The glasses forget their notes on a
/// power cycle or a firmware hiccup, and nothing used to put them back, so a
/// slot the user filled would simply be gone the next time they looked. Every
/// reconnection now replays what the phone holds.
class QuickNotesService {
  QuickNotesService._internal();
  static final QuickNotesService singleton = QuickNotesService._internal();
  factory QuickNotesService() => singleton;

  /// The hardware exposes exactly four slots, numbered 1 to 4.
  static const int slotCount = 4;

  static const String _boxName = 'quickNotes';
  static const String _revisionKey = 'revision';

  StreamSubscription<bool>? _connectionSubscription;

  /// Starts replaying the stored notes whenever the glasses come back.
  Future<void> start() async {
    await _openBox();

    _connectionSubscription ??=
        BluetoothManager.singleton.connectionStatusStream.listen((connected) {
      if (connected) unawaited(pushAll());
    });

    if (BluetoothManager.singleton.isConnected) await pushAll();
  }

  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }

  Future<QuickNote> read(int slot) async {
    final box = await _openBox();
    final stored = box.get('slot_$slot') as Map?;
    return QuickNote(
      slot: slot,
      title: stored?['title'] as String? ?? '',
      body: stored?['body'] as String? ?? '',
    );
  }

  Future<List<QuickNote>> readAll() async =>
      [for (var slot = 1; slot <= slotCount; slot++) await read(slot)];

  /// Stores a note and sends it to the glasses.
  Future<void> save(QuickNote note) async {
    final box = await _openBox();
    await box.put('slot_${note.slot}', note.toMap());
    await _send(note);
  }

  Future<void> clear(int slot) async {
    final box = await _openBox();
    await box.delete('slot_$slot');
    await _send(QuickNote(slot: slot, title: '', body: ''));
  }

  /// Replays every stored slot, in order, so the glasses match the phone.
  Future<void> pushAll() async {
    if (!BluetoothManager.singleton.isConnected) return;

    for (final note in await readAll()) {
      await _send(note);
      // The firmware drops writes that arrive back to back.
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> _send(QuickNote note) async {
    if (!BluetoothManager.singleton.isConnected) return;

    try {
      await BluetoothManager.singleton.sendNote(
        Note(
          noteNumber: note.slot,
          name: note.title.isEmpty && !note.isEmpty
              ? 'Note ${note.slot}'
              : note.title,
          text: note.body,
          revision: await _nextRevision(),
        ),
      );
    } catch (e) {
      debugPrint('QuickNotesService: could not send slot ${note.slot}: $e');
    }
  }

  /// A counter that only moves forward, shared by all four slots.
  Future<int> _nextRevision() async {
    final box = await _openBox();
    final next = ((box.get(_revisionKey) as int?) ?? 0) + 1;
    await box.put(_revisionKey, next);
    return next;
  }

  Future<Box> _openBox() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);
}
