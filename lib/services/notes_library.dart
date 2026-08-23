import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/models/g1/note_slots.dart';
import 'package:g1_extended/models/note_entry.dart';

/// Every note the phone holds, and which four are on the glasses.
///
/// The hardware keeps four notes. The app used to keep exactly four as well,
/// one per slot, so writing a fifth meant destroying one — and there was no
/// way to keep something written last week without giving up a slot to it.
/// The library holds as many as you like; pinning decides which four the
/// glasses get.
///
/// Pinning a fifth is refused rather than resolved by evicting something.
/// Silently dropping a note the wearer wrote is the failure this whole area
/// has been suffering from, and doing it deliberately would not be an
/// improvement over doing it by accident.
class NotesLibrary {
  NotesLibrary._internal();
  static final NotesLibrary singleton = NotesLibrary._internal();
  factory NotesLibrary() => singleton;

  static const String _boxName = 'quickNotes';
  static const String _entryPrefix = 'note_';
  static const String _revisionKey = 'revision';
  static const String _migratedKey = 'migrated_to_library';

  /// The firmware exposes slots 1 to 4.
  static const int slotCount = NoteSlots.count;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires whenever anything is added, edited, pinned or removed.
  Stream<void> get changes => _changes.stream;

  Future<Box> _openBox() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  /// Brings forward anything written by the four-slot version.
  ///
  /// That version stored one entry per slot under `slot_N`. Those are real
  /// notes somebody wrote, so they become library entries pinned to the slot
  /// they were already in, rather than being left behind in a format nothing
  /// reads any more.
  Future<void> migrate() async {
    final box = await _openBox();
    if (box.get(_migratedKey) == true) return;

    for (var slot = 1; slot <= slotCount; slot++) {
      final stored = box.get('slot_$slot');
      if (stored is! Map) continue;

      final title = stored['title'] as String? ?? '';
      final body = stored['body'] as String? ?? '';
      if (title.isEmpty && body.isEmpty) continue;

      final entry = NoteEntry(
        id: _newId(),
        title: title,
        body: body,
        updatedAt: DateTime.now(),
        pinnedSlot: slot,
      );
      await box.put('$_entryPrefix${entry.id}', entry.toMap());
      debugPrint('NotesLibrary: brought slot $slot forward as ${entry.id}');
    }

    for (var slot = 1; slot <= slotCount; slot++) {
      await box.delete('slot_$slot');
    }
    await box.put(_migratedKey, true);
  }

  /// Every note, most recently touched first, pinned ones ahead of the rest.
  Future<List<NoteEntry>> all() async {
    final box = await _openBox();
    final entries = <NoteEntry>[];

    for (final key in box.keys) {
      if (key is! String || !key.startsWith(_entryPrefix)) continue;
      final entry = NoteEntry.fromMap(box.get(key));
      if (entry != null) entries.add(entry);
    }

    entries.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isPinned && b.isPinned) {
        return a.pinnedSlot!.compareTo(b.pinnedSlot!);
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return entries;
  }

  Future<NoteEntry?> byId(String id) async {
    final box = await _openBox();
    return NoteEntry.fromMap(box.get('$_entryPrefix$id'));
  }

  /// Creates a note. Pins it only if a slot happens to be free.
  Future<NoteEntry> create({
    String title = '',
    String body = '',
    bool pinIfPossible = false,
  }) async {
    final slot = pinIfPossible ? await firstFreeSlot() : null;

    final entry = NoteEntry(
      id: _newId(),
      title: title,
      body: body,
      updatedAt: DateTime.now(),
      pinnedSlot: slot,
    );

    await _put(entry);
    return entry;
  }

  /// Writes an edited note. Silently does nothing for an unknown id.
  Future<void> update(NoteEntry entry) =>
      _put(entry.copyWith(updatedAt: DateTime.now()));

  Future<void> remove(String id) async {
    final box = await _openBox();
    await box.delete('$_entryPrefix$id');
    _changes.add(null);
  }

  /// The lowest slot with nothing in it, or null when all four are taken.
  Future<int?> firstFreeSlot() async {
    final taken = {
      for (final entry in await all())
        if (entry.pinnedSlot != null) entry.pinnedSlot!,
    };
    for (var slot = 1; slot <= slotCount; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    return null;
  }

  /// Puts a note on the glasses.
  ///
  /// [slot] picks one; leaving it out takes the first free one. Refused
  /// rather than resolved when there is no room, so the interface can say
  /// which note is in the way instead of quietly removing it.
  Future<PinResult> pin(String id, {int? slot}) async {
    final entry = await byId(id);
    if (entry == null) return const PinResult.ok();

    if (slot == null) {
      final free = await firstFreeSlot();
      if (free == null) {
        return const PinResult.refused(PinRefusal.noFreeSlot);
      }
      await _put(entry.copyWith(pinnedSlot: free));
      return const PinResult.ok();
    }

    if (slot < 1 || slot > slotCount) return const PinResult.ok();

    final occupant = (await all()).where((e) => e.pinnedSlot == slot).cast<NoteEntry?>().firstWhere(
          (e) => e!.id != id,
          orElse: () => null,
        );

    if (occupant != null) {
      return PinResult.refused(PinRefusal.slotTaken, occupiedBy: occupant);
    }

    await _put(entry.copyWith(pinnedSlot: slot));
    return const PinResult.ok();
  }

  Future<void> unpin(String id) async {
    final entry = await byId(id);
    if (entry == null) return;
    await _put(entry.copyWith(clearPin: true));
  }

  /// What the glasses should show, keyed by slot.
  Future<Map<int, SlotContent>> pinnedSlots() async {
    final result = <int, SlotContent>{};
    for (final entry in await all()) {
      final slot = entry.pinnedSlot;
      if (slot == null || entry.isEmpty) continue;
      result[slot] = SlotContent(
        name: entry.displayTitle,
        text: entry.body,
        fromUser: true,
      );
    }
    return result;
  }

  /// A counter that only ever moves forward, shared by every slot.
  ///
  /// The revision used to come from the clock, which wraps every 256 seconds,
  /// so two writes minutes apart could carry the same value or the newer one
  /// a lower value than the older.
  Future<int> nextRevision() async {
    final box = await _openBox();
    final next = ((box.get(_revisionKey) as int?) ?? 0) + 1;
    await box.put(_revisionKey, next);
    return next;
  }

  Future<void> _put(NoteEntry entry) async {
    final box = await _openBox();
    await box.put('$_entryPrefix${entry.id}', entry.toMap());
    _changes.add(null);
  }

  static final Random _random = Random();

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';
}
