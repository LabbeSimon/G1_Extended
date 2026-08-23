import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/models/g1/note_markup.dart';

/// What the keyboard can type, translated to what the lens can draw. The
/// stored note is never rewritten — this runs at the border, on the way out.
void main() {
  const box = NoteSupportedIcons.CHECKBOX;
  const tick = NoteSupportedIcons.CHECK;

  group('Checkbox markup', () {
    test('an empty pair becomes an empty box', () {
      expect(NoteMarkup.toLens('[] milk'), '$box milk');
      expect(NoteMarkup.toLens('[ ] milk'), '$box milk');
    });

    test('a crossed pair becomes a check', () {
      expect(NoteMarkup.toLens('[x] bread'), '$tick bread');
      expect(NoteMarkup.toLens('[X] bread'), '$tick bread');
    });

    test('a dash is a thing to do', () {
      expect(NoteMarkup.toLens('- eggs'), '$box eggs');
      expect(NoteMarkup.toLens('* eggs'), '$box eggs');
    });

    test('each line is translated on its own', () {
      expect(
        NoteMarkup.toLens('[] milk\n[x] bread\nplain line'),
        '$box milk\n$tick bread\nplain line',
      );
    });

    test('leading spaces do not defeat it', () {
      expect(NoteMarkup.toLens('  [] indented'), '$box indented');
    });
  });

  group('What must pass through untouched', () {
    test('numbers are already typable, so they are kept as written', () {
      expect(NoteMarkup.toLens('1. preheat\n2. mix'), '1. preheat\n2. mix');
    });

    test('a line with no markup is a line, not a mistake', () {
      expect(NoteMarkup.toLens('call the plumber'), 'call the plumber');
    });

    test('brackets in the middle of a sentence stay where they are', () {
      expect(NoteMarkup.toLens('see [x] in the manual'),
          'see [x] in the manual');
    });

    test('a dash with no space after it is a word, not a list', () {
      expect(NoteMarkup.toLens('-20 degrees tonight'), '-20 degrees tonight');
    });

    test('the empty note survives', () {
      expect(NoteMarkup.toLens(''), '');
    });
  });
}
