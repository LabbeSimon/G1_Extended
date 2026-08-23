import 'package:flutter/services.dart';

/// Cursor-aware edits behind the note editor's toolbar buttons.
///
/// Pure functions over (text, selection), because insertion at a cursor is
/// exactly the kind of logic that is always almost right: off by one at the
/// start of a line, wrong on the empty field, cursor left behind the
/// inserted text. Each case is pinned by a test instead of discovered by a
/// user mid-sentence.
abstract final class NoteEditing {
  /// Puts [prefix] at the start of the line the cursor is on.
  ///
  /// If the line already starts with it, it is removed instead — the same
  /// button toggles, which is what fingers expect of it.
  static TextEditingValue toggleLinePrefix(
    TextEditingValue value,
    String prefix,
  ) {
    final text = value.text;
    final cursor = value.selection.isValid ? value.selection.start : text.length;
    final lineStart = text.lastIndexOf('\n', cursor - 1 < 0 ? 0 : cursor - 1) + 1;

    if (text.startsWith(prefix, lineStart)) {
      final removed = text.replaceRange(lineStart, lineStart + prefix.length, '');
      final shifted = (cursor - prefix.length).clamp(lineStart, removed.length);
      return TextEditingValue(
        text: removed,
        selection: TextSelection.collapsed(offset: shifted),
      );
    }

    final inserted = text.replaceRange(lineStart, lineStart, prefix);
    return TextEditingValue(
      text: inserted,
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }

  /// Puts the next number at the start of the cursor's line: one more than
  /// the previous line's number when it has one, "1. " otherwise.
  static TextEditingValue numberLine(TextEditingValue value) {
    final text = value.text;
    final cursor = value.selection.isValid ? value.selection.start : text.length;
    final lineStart = text.lastIndexOf('\n', cursor - 1 < 0 ? 0 : cursor - 1) + 1;

    var number = 1;
    if (lineStart > 0) {
      final previousStart =
          text.lastIndexOf('\n', lineStart - 2 < 0 ? 0 : lineStart - 2) + 1;
      final previousLine = text.substring(previousStart, lineStart - 1);
      final match = RegExp(r'^\s*(\d+)\.').firstMatch(previousLine);
      if (match != null) number = int.parse(match.group(1)!) + 1;
    }

    return toggleLinePrefix(value, '$number. ');
  }
}
