import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'package:g1_extended/models/g1/note_markup.dart';
import 'package:g1_extended/models/g1/note_slots.dart';
import 'package:g1_extended/models/note_entry.dart';

/// Every note the phone holds, and which four are on the glasses.
///
/// The hardware keeps four notes. The app used to keep exactly four as
/// well, so writing a fifth meant destroying one; the library holds as many
/// as you like and pinning decides which four go across. Pinning a fifth is
/// refused rather than resolved by evicting something — silently dropping
/// what someone wrote is the failure this whole area suffered from.
///
/// Stored as one JSON file rather than in Hive, and that is the point.
/// Hive is per-isolate: the interface has one instance and the background
/// service another, and the service is the isolate that holds the glasses
/// — so it is the one that receives a note dictated from the temple. Two
/// Hive instances over one box file do not see each other's writes and can
/// lose them outright, which is why a note could be confirmed on the lens
/// and be absent from the notes screen a second later. A file, re-read
/// whenever the other isolate has touched it, is what they can share.
class NotesLibrary {
  NotesLibrary._internal();
  static final NotesLibrary singleton = NotesLibrary._internal();
  factory NotesLibrary() => singleton;

  /// The firmware exposes slots 1 to 4.
  static const int slotCount = NoteSlots.count;

  static const String _fileName = 'notes.json';

  /// The box the four-slot and Hive-backed versions wrote to.
  static const String _legacyBox = 'quickNotes';

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires whenever anything is added, edited, pinned or removed.
  Stream<void> get changes => _changes.stream;

  /// Overridable so tests need no platform channel.
  @visibleForTesting
  static Directory? directoryForTest;

  final Map<String, NoteEntry> _entries = {};
  int _revision = 0;

  /// The modification time this isolate last read. Comparing it is a stat
  /// call — cheap enough to do before every read, which is what keeps the
  /// two isolates honest with each other.
  DateTime? _seenAt;
  bool _loaded = false;

  Future<File> _file() async {
    final dir = directoryForTest ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _load({bool force = false}) async {
    final file = await _file();

    if (!await file.exists()) {
      _loaded = true;
      return;
    }

    final modified = await file.lastModified();
    if (!force && _loaded && _seenAt != null && !modified.isAfter(_seenAt!)) {
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      _entries.clear();
      final list = decoded['notes'];
      if (list is List) {
        for (final raw in list) {
          final entry = NoteEntry.fromMap(raw);
          if (entry != null) _entries[entry.id] = entry;
        }
      }
      // Never let a reload walk the revision backwards: the glasses use it
      // to tell one write from the next, and a repeat looks like no change.
      final stored = decoded['revision'];
      if (stored is int && stored > _revision) _revision = stored;

      _seenAt = modified;
      _loaded = true;
    } catch (e) {
      debugPrint('NotesLibrary: unreadable store, starting empty: $e');
      _loaded = true;
    }
  }

  /// Writes through a temporary file and renames it into place, so a note
  /// is never half-written — the same reasoning as the speech model's
  /// staging directory.
  Future<void> _save() async {
    final file = await _file();
    final temporary = File('${file.path}.writing');

    final payload = jsonEncode({
      'revision': _revision,
      'notes': [for (final entry in _entries.values) entry.toMap()],
    });

    try {
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
      _seenAt = await file.lastModified();
    } catch (e) {
      debugPrint('NotesLibrary: could not save: $e');
    }
  }

  /// Brings forward anything an older version wrote.
  ///
  /// Two shapes have existed: one Hive entry per slot, then Hive entries
  /// keyed `note_<id>`. Both are real notes somebody wrote, so both become
  /// library entries rather than being left in a format nothing reads.
  Future<void> migrate() async {
    await _load(force: true);

    Box? box;
    try {
      box = Hive.isBoxOpen(_legacyBox)
          ? Hive.box(_legacyBox)
          : await Hive.openBox(_legacyBox);
    } catch (e) {
      // No Hive in this isolate, or no such box. Nothing to bring forward.
      debugPrint('NotesLibrary: no legacy store to migrate: $e');
      return;
    }

    var imported = 0;

    for (final key in box.keys.toList()) {
      if (key is! String) continue;

      if (key.startsWith('note_')) {
        final entry = NoteEntry.fromMap(box.get(key));
        if (entry != null && !_entries.containsKey(entry.id)) {
          _entries[entry.id] = entry;
          imported++;
        }
        await box.delete(key);
        continue;
      }

      if (key.startsWith('slot_')) {
        final slot = int.tryParse(key.substring(5));
        final stored = box.get(key);
        if (slot != null && stored is Map) {
          final title = stored['title'] as String? ?? '';
          final body = stored['body'] as String? ?? '';
          if (title.isNotEmpty || body.isNotEmpty) {
            final entry = NoteEntry(
              id: _newId(),
              title: title,
              body: body,
              updatedAt: DateTime.now(),
              pinnedSlot: slot >= 1 && slot <= slotCount ? slot : null,
            );
            _entries[entry.id] = entry;
            imported++;
          }
        }
        await box.delete(key);
        continue;
      }

      if (key == 'revision') {
        final stored = box.get(key);
        if (stored is int && stored > _revision) _revision = stored;
      }
    }

    if (imported > 0) debugPrint('NotesLibrary: brought $imported note(s) forward');
    await _save();
  }

  /// Every note, pinned ones first in slot order, then most recent.
  Future<List<NoteEntry>> all() async {
    await _load();
    final entries = _entries.values.toList();

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
    await _load();
    return _entries[id];
  }

  /// Creates a note. Pins it only if a slot happens to be free.
  Future<NoteEntry> create({
    String title = '',
    String body = '',
    bool pinIfPossible = false,
  }) async {
    await _load();
    final slot = pinIfPossible ? _firstFreeSlot() : null;

    final entry = NoteEntry(
      id: _newId(),
      title: title,
      body: body,
      updatedAt: DateTime.now(),
      pinnedSlot: slot,
    );

    _entries[entry.id] = entry;
    await _save();
    _changes.add(null);
    return entry;
  }

  /// Writes an edited note. Unknown ids are ignored.
  Future<void> update(NoteEntry entry) async {
    await _load();
    if (!_entries.containsKey(entry.id)) return;
    _entries[entry.id] = entry.copyWith(updatedAt: DateTime.now());
    await _save();
    _changes.add(null);
  }

  Future<void> remove(String id) async {
    await _load();
    _entries.remove(id);
    await _save();
    _changes.add(null);
  }

  /// The lowest slot with nothing in it, or null when all four are taken.
  Future<int?> firstFreeSlot() async {
    await _load();
    return _firstFreeSlot();
  }

  int? _firstFreeSlot() {
    final taken = {
      for (final entry in _entries.values)
        if (entry.pinnedSlot != null) entry.pinnedSlot!,
    };
    for (var slot = 1; slot <= slotCount; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    return null;
  }

  /// Puts a note on the glasses.
  ///
  /// Refused rather than resolved when there is no room, so the interface
  /// can name what is in the way instead of quietly removing it.
  Future<PinResult> pin(String id, {int? slot}) async {
    await _load();
    final entry = _entries[id];
    if (entry == null) return const PinResult.ok();

    if (slot == null) {
      final free = _firstFreeSlot();
      if (free == null) {
        return const PinResult.refused(PinRefusal.noFreeSlot);
      }
      _entries[id] = entry.copyWith(pinnedSlot: free);
      await _save();
      _changes.add(null);
      return const PinResult.ok();
    }

    if (slot < 1 || slot > slotCount) return const PinResult.ok();

    for (final other in _entries.values) {
      if (other.id != id && other.pinnedSlot == slot) {
        return PinResult.refused(PinRefusal.slotTaken, occupiedBy: other);
      }
    }

    _entries[id] = entry.copyWith(pinnedSlot: slot);
    await _save();
    _changes.add(null);
    return const PinResult.ok();
  }

  Future<void> unpin(String id) async {
    await _load();
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(clearPin: true);
    await _save();
    _changes.add(null);
  }

  /// What the glasses should show, keyed by slot.
  Future<Map<int, SlotContent>> pinnedSlots() async {
    final result = <int, SlotContent>{};
    for (final entry in await all()) {
      final slot = entry.pinnedSlot;
      if (slot == null || entry.isEmpty) continue;
      result[slot] = SlotContent(
        name: entry.displayTitle,
        // Checkbox markup becomes the firmware's glyphs here, at the border
        // between phone and lens. The stored note keeps what was typed.
        text: NoteMarkup.toLens(entry.body),
        fromUser: true,
      );
    }
    return result;
  }

  /// A counter that only ever moves forward, shared by every slot and by
  /// both isolates — the glasses use it to tell one write from the next.
  Future<int> nextRevision() async {
    await _load();
    _revision += 1;
    await _save();
    return _revision;
  }

  /// For tests that simulate a second isolate.
  @visibleForTesting
  void resetForTest() {
    _entries.clear();
    _revision = 0;
    _seenAt = null;
    _loaded = false;
  }

  static final Random _random = Random();

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';
}
