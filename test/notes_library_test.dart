import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/models/note_entry.dart';
import 'package:g1_extended/services/notes_library.dart';

/// The glasses hold four notes; the phone holds as many as you like. Which
/// four go across is the pin. What these guard is that nothing the wearer
/// wrote is ever removed to make room — that silent removal is the bug this
/// whole area suffered from.
void main() {
  late Directory dir;
  final library = NotesLibrary.singleton;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('notes-');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  group('Pinning', () {
    test('a new note is not on the glasses unless asked', () async {
      final note = await library.create(title: 'a', body: 'b');
      expect(note.isPinned, isFalse);
      expect(await library.pinnedSlots(), isEmpty);
    });

    test('pinning takes the lowest free slot', () async {
      final first = await library.create(body: 'one');
      final second = await library.create(body: 'two');

      await library.pin(first.id);
      await library.pin(second.id);

      final slots = await library.pinnedSlots();
      expect(slots[1]!.text, 'one');
      expect(slots[2]!.text, 'two');
    });

    test('a fifth pin is refused, not resolved by evicting one', () async {
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        final note = await library.create(body: 'note $i');
        ids.add(note.id);
        expect((await library.pin(note.id)).succeeded, isTrue);
      }

      final fifth = await library.create(body: 'the fifth');
      final result = await library.pin(fifth.id);

      expect(result.succeeded, isFalse);
      expect(result.refusal, PinRefusal.noFreeSlot);

      // And crucially, nothing was lost to make room.
      final slots = await library.pinnedSlots();
      expect(slots.length, 4);
      expect((await library.byId(fifth.id))!.isPinned, isFalse);
      for (final id in ids) {
        expect((await library.byId(id))!.isPinned, isTrue);
      }
    });

    test('asking for a taken slot names the note in the way', () async {
      final first = await library.create(title: 'shopping', body: 'x');
      await library.pin(first.id, slot: 3);

      final second = await library.create(body: 'y');
      final result = await library.pin(second.id, slot: 3);

      expect(result.refusal, PinRefusal.slotTaken);
      expect(result.occupiedBy!.displayTitle, 'shopping');
    });

    test('unpinning frees the slot for the next note', () async {
      final first = await library.create(body: 'one');
      await library.pin(first.id, slot: 2);
      await library.unpin(first.id);

      final second = await library.create(body: 'two');
      await library.pin(second.id);

      expect((await library.pinnedSlots())[1]!.text, 'two');
      // And the unpinned note is still there.
      expect(await library.byId(first.id), isNotNull);
    });

    test('an empty note takes no slot on the glasses', () async {
      final note = await library.create(title: '  ', body: '  ');
      await library.pin(note.id, slot: 1);
      expect(await library.pinnedSlots(), isEmpty);
    });
  });

  group('The library outlives the four slots', () {
    test('unpinned notes are kept, not discarded', () async {
      for (var i = 0; i < 12; i++) {
        await library.create(body: 'note $i');
      }
      expect((await library.all()).length, 12);
    });

    test('pinned notes are listed first, in slot order', () async {
      final a = await library.create(body: 'a');
      await library.create(body: 'b');
      final c = await library.create(body: 'c');

      await library.pin(c.id, slot: 1);
      await library.pin(a.id, slot: 2);

      final all = await library.all();
      expect(all[0].body, 'c');
      expect(all[1].body, 'a');
      expect(all[2].body, 'b');
    });
  });

  group('Bringing the old four-slot notes forward', () {
    test('each becomes a library note pinned where it already was', () async {
      final box = await Hive.openBox('quickNotes');
      await box.put('slot_1', {'title': 'door', 'body': '4417'});
      await box.put('slot_3', {'title': '', 'body': 'milk'});
      await box.put('slot_4', {'title': '', 'body': ''});

      await library.migrate();

      final slots = await library.pinnedSlots();
      expect(slots[1]!.text, '4417');
      expect(slots[3]!.text, 'milk');
      expect(slots.containsKey(4), isFalse, reason: 'an empty slot is not a note');
      expect((await library.all()).length, 2);
    });

    test('running twice does not duplicate anything', () async {
      final box = await Hive.openBox('quickNotes');
      await box.put('slot_1', {'title': 'door', 'body': '4417'});

      await library.migrate();
      await library.migrate();

      expect((await library.all()).length, 1);
    });
  });

  group('A damaged entry does not take the screen down', () {
    test('unreadable records are skipped rather than thrown on', () async {
      final box = await Hive.openBox('quickNotes');
      await box.put('note_broken', 'not a map');
      await box.put('note_noid', {'title': 'x'});

      expect(await library.all(), isEmpty);
    });

    test('a slot outside the hardware range is treated as unpinned', () async {
      final box = await Hive.openBox('quickNotes');
      await box.put('note_x', {
        'id': 'x',
        'title': 't',
        'body': 'b',
        'updatedAt': 0,
        'pinnedSlot': 9,
      });

      expect((await library.byId('x'))!.isPinned, isFalse);
    });
  });

  group('The revision counter only moves forward', () {
    test('successive calls never repeat or go backwards', () async {
      var previous = 0;
      for (var i = 0; i < 50; i++) {
        final next = await library.nextRevision();
        expect(next, greaterThan(previous));
        previous = next;
      }
    });
  });
}
