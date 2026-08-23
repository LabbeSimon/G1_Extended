import 'package:g1_extended/models/g1/note.dart';

/// The light markup a note can carry, translated for the lens.
///
/// The official app's notes can show checkbox and check glyphs; the phone
/// keyboard cannot type them. So the editor accepts what a keyboard can
/// produce and the translation happens at the moment the note is written to
/// the glasses — the stored text stays exactly what the user typed.
///
///   [] milk        →  ☐ milk
///   [x] bread      →  ✓ bread
///   - eggs         →  ☐ eggs
///   1. preheat     →  1. preheat   (numbers are already typable; kept)
///
/// Nothing else is touched. A line that uses no markup is a line, not a
/// mistake.
abstract final class NoteMarkup {
  static final RegExp _unchecked = RegExp(r'^\s*(\[\s?\]|-|\*)\s+');
  static final RegExp _checked = RegExp(r'^\s*\[[xX]\]\s+');

  /// Translates one note body for the lens.
  static String toLens(String text) =>
      text.split('\n').map(_line).join('\n');

  static String _line(String line) {
    final checked = _checked.firstMatch(line);
    if (checked != null) {
      return '${NoteSupportedIcons.CHECK} ${line.substring(checked.end)}';
    }
    final unchecked = _unchecked.firstMatch(line);
    if (unchecked != null) {
      return '${NoteSupportedIcons.CHECKBOX} ${line.substring(unchecked.end)}';
    }
    return line;
  }
}
