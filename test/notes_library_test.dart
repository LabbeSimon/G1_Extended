import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/note_entry.dart';
import 'package:g1_extended/services/notes_library.dart';

/// The glasses hold four notes; the phone holds as many as you like, and
/// the pin decides which four go across. What these guard above all is that
/// nothing anyone wrote is ever removed to make room — and that a note
/// written by one isolate is visible to the other, which is the bug that
/// had the lens confirm "Noted" over an empty notes screen.
void main() {
  late Directory dir;
  final library = NotesLibrary.singleton;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('notes-');
    NotesLibrary.directoryForTest = dir;
    library.resetForTest();
  });

  tearDown(() {
    NotesLibrary.directoryForTest = null;
    library.resetForTest();
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

    test('a fifth pin is refused, and nothing is lost to make room',
        () async {
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        final note = await library.create(body: 'note $i');
        ids.add(note.id);
        expect((await library.pin(note.id)).succeeded, isTrue);
      }

      final fifth = await library.create(body: 'the fifth');
      final result = await library.pin(fifth.id);

      expect(result.refusal, PinRefusal.noFreeSlot);
      expect((await library.pinnedSlots()).length, 4);
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

    test('unpinning frees the slot and keeps the note', () async {
      final first = await library.create(body: 'one');
      await library.pin(first.id, slot: 2);
      await library.unpin(first.id);

      final second = await library.create(body: 'two');
      await library.pin(second.id);

      expect((await library.pinnedSlots())[1]!.text, 'two');
      expect(await library.byId(first.id), isNotNull);
    });
  });

  group('The file bridges the isolates', () {
    test('a note dictated in one isolate is listed by the other', () async {
      // The background service holds the glasses, so it receives the temple
      // hold and creates the note.
      await library.create(title: 'Note', body: 'acheter du pain');

      // The interface isolate, born knowing nothing.
      library.resetForTest();

      final all = await library.all();
      expect(all, hasLength(1),
          reason: '"Noted" on the lens over an empty notes screen is the '
              'bug this exists to prevent');
      expect(all.first.body, 'acheter du pain');
    });

    test('a second isolate sees an edit, not a stale copy', () async {
      final note = await library.create(body: 'first');
      library.resetForTest();
      await library.all();

      // Something else edits the same note through the shared file.
      final other = NotesLibrary.singleton;
      await other.update(note.copyWith(body: 'edited'));

      expect((await library.byId(note.id))!.body, 'edited');
    });

    test('the revision counter never walks backwards on reload', () async {
      for (var i = 0; i < 5; i++) {
        await library.nextRevision();
      }
      library.resetForTest();

      final next = await library.nextRevision();
      expect(next, greaterThan(5),
          reason: 'a repeated revision looks to the glasses like no change '
              'at all');
    });
  });

  group('Damaged data degrades quietly', () {
    test('an unreadable store starts empty rather than throwing', () async {
      File('${dir.path}/notes.json').writeAsStringSync('{not json');
      expect(await library.all(), isEmpty);
    });

    test('a malformed entry is skipped, the rest survive', () async {
      File('${dir.path}/notes.json').writeAsStringSync(
        '{"revision":1,"notes":[{"no":"id"},'
        '{"id":"k","title":"t","body":"b","updatedAt":0,"pinnedSlot":null}]}',
      );
      final all = await library.all();
      expect(all, hasLength(1));
      expect(all.first.id, 'k');
    });

    test('a slot outside the hardware range reads as unpinned', () async {
      File('${dir.path}/notes.json').writeAsStringSync(
        '{"notes":[{"id":"x","title":"t","body":"b","updatedAt":0,'
        '"pinnedSlot":9}]}',
      );
      expect((await library.byId('x'))!.isPinned, isFalse);
    });
  });

  group('An empty note holds no slot on the glasses', () {
    test('blank text releases the slot', () async {
      final note = await library.create(title: '  ', body: '  ');
      await library.pin(note.id, slot: 1);
      expect(await library.pinnedSlots(), isEmpty);
    });
  });
}
