import 'package:flutter/foundation.dart';

/// A script the glasses either can or cannot draw.
enum ScriptSupport {
  /// Latin, digits, punctuation, and the CJK the display does carry.
  supported,

  /// Cyrillic, Arabic, Devanagari and the rest the font has no glyphs for.
  unsupported,
}

/// Guards against sending the lens characters it cannot draw.
///
/// Even Realities list Russian, Arabic, Hindi, Bengali and traditional
/// Chinese as languages that "cannot be displayed" — the display carries
/// Latin, Japanese, Korean and simplified Chinese, and nothing else. Text in
/// the others does not fail loudly; it comes out as blank boxes, which looks
/// like the app is broken rather than like the hardware has a limit.
///
/// So the text is checked before it is sent, and what cannot be drawn is
/// replaced by something that says so.
abstract final class GlassesText {
  /// Ranges the display has no glyphs for.
  static const List<({int start, int end, String name})> _unsupportedRanges = [
    (start: 0x0400, end: 0x052F, name: 'Cyrillic'),
    (start: 0x0590, end: 0x05FF, name: 'Hebrew'),
    (start: 0x0600, end: 0x06FF, name: 'Arabic'),
    (start: 0x0700, end: 0x074F, name: 'Syriac'),
    (start: 0x0900, end: 0x097F, name: 'Devanagari'),
    (start: 0x0980, end: 0x09FF, name: 'Bengali'),
    (start: 0x0E00, end: 0x0E7F, name: 'Thai'),
    (start: 0x10A0, end: 0x10FF, name: 'Georgian'),
    (start: 0x0530, end: 0x058F, name: 'Armenian'),
  ];

  /// Names the scripts in [text] that the glasses cannot draw.
  static List<String> unsupportedScripts(String text) {
    final found = <String>{};

    for (final rune in text.runes) {
      for (final range in _unsupportedRanges) {
        if (rune >= range.start && rune <= range.end) {
          found.add(range.name);
          break;
        }
      }
    }

    return found.toList()..sort();
  }

  static bool canDisplay(String text) => unsupportedScripts(text).isEmpty;

  /// Returns text safe to send, or a short explanation when it is not.
  ///
  /// A caller that would rather handle it another way can ask
  /// [unsupportedScripts] first; this is the sensible default.
  static String prepare(String text) {
    final unsupported = unsupportedScripts(text);
    if (unsupported.isEmpty) return text;

    debugPrint('GlassesText: dropping ${unsupported.join(', ')}');
    return 'The glasses cannot show ${unsupported.join(' or ')} text';
  }
}
