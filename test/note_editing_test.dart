import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/note_editing.dart';

TextEditingValue at(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

/// Cursor-at-line-start, empty field, mid-word, toggling off — the four
/// places insertion logic is always almost right.
void main() {
  group('Toggling a checkbox prefix', () {
    test('prefixes the cursor line, not the first line', () {
      final result =
          NoteEditing.toggleLinePrefix(at('milk\nbread', 8), '[] ');
      expect(result.text, 'milk\n[] bread');
      expect(result.selection.start, 11);
    });

    test('works on an empty note', () {
      final result = NoteEditing.toggleLinePrefix(at('', 0), '[] ');
      expect(result.text, '[] ');
      expect(result.selection.start, 3);
    });

    test('works with the cursor mid-word', () {
      final result = NoteEditing.toggleLinePrefix(at('milk', 2), '[] ');
      expect(result.text, '[] milk');
      expect(result.selection.start, 5);
    });

    test('pressing it again removes the prefix', () {
      final once = NoteEditing.toggleLinePrefix(at('milk', 4), '[] ');
      final twice = NoteEditing.toggleLinePrefix(once, '[] ');
      expect(twice.text, 'milk');
      expect(twice.selection.start, 4);
    });

    test('the last line of several is the one touched', () {
      final result = NoteEditing.toggleLinePrefix(at('a\nb\nc', 5), '[x] ');
      expect(result.text, 'a\nb\n[x] c');
    });
  });

  group('Numbering', () {
    test('a first item starts at one', () {
      final result = NoteEditing.numberLine(at('preheat', 7));
      expect(result.text, '1. preheat');
    });

    test('follows the previous line\'s number', () {
      final result = NoteEditing.numberLine(at('1. preheat\nmix', 14));
      expect(result.text, '1. preheat\n2. mix');
    });

    test('counts on from any number, not from the count of lines', () {
      final result = NoteEditing.numberLine(at('7. seven\neight', 14));
      expect(result.text, '7. seven\n8. eight');
    });

    test('a previous line without a number restarts at one', () {
      final result = NoteEditing.numberLine(at('title\nfirst', 11));
      expect(result.text, 'title\n1. first');
    });
  });
}
