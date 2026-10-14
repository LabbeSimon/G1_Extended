// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The glasses' language ids for their translation screen, as the official
/// Even app 1.6.5 numbers them (docs/protocol/even-ai-transcribe-translate.md).
abstract final class TranslateLanguages {
  static const int CHINESE = 0x01;
  static const int ENGLISH = 0x02;
  static const int FRENCH = 0x05;
  static const int DUTCH = 0x09;

  static const Map<String, int> _byCode = {
    'zh': 1,
    'en': 2,
    'ja': 3,
    'ko': 4,
    'fr': 5,
    'de': 6,
    'es': 7,
    'ru': 8,
    'nl': 9,
    'no': 10,
    'nb': 10,
    'da': 11,
    'sv': 12,
    'fi': 13,
    'it': 14,
    'ar': 15,
    'hi': 16,
    'bn': 17,
    'pl': 19,
    'cs': 20,
    'tr': 21,
    'pt': 22,
    'uk': 23,
    'el': 24,
    'hu': 25,
  };

  /// The id for a two-letter language code, English when the glasses have
  /// none for it.
  static int forCode(String code) => _byCode[code] ?? ENGLISH;
}

/// The glasses' own translation screen: an upper area for what was heard
/// (0x0F) and a lower one for its translation (0x0D), opened and closed with
/// 0x1C. Frames as the official Even app 1.6.5 builds them.
class Translate {
  Translate({required this.fromLanguage, required this.toLanguage});

  final int fromLanguage;
  final int toLanguage;

  /// Text per packet: seven header bytes plus this makes 200.
  static const int _chunk = 193;

  /// Lines the official app keeps on screen, oldest dropped first.
  static const int maxLines = 5;

  int _statusSeq = 0;
  int _heardSeq = 0;
  int _translatedSeq = 0;

  /// Asks each temple what it is showing, as the official app does before
  /// it starts a feature. The answer is not needed here.
  Uint8List buildSetupCommand() =>
      Uint8List.fromList([0x39, 0x05, 0x00, _statusSeq++ % 255, 0x01]);

  /// Asks the right temple whether a feature may start. Byte 5 of the
  /// answer: 1 now, 2 once the open feature is closed.
  Uint8List buildRightGlassStartCommand() =>
      Uint8List.fromList([0x50, 0x06, 0x00, 0x00, 0x01, 0x01]);

  Uint8List buildStartCommand() =>
      Uint8List.fromList([0x1C, 0x00, fromLanguage, toLanguage]);

  Uint8List buildStopCommand() =>
      Uint8List.fromList([0x1C, 0x01, fromLanguage, toLanguage]);

  /// Starts translating and clears both areas.
  List<Uint8List> buildInitalScreenLoad() => [
        buildStartCommand(),
        ...buildOriginalCommand('\r'),
        ...buildTranslatedCommand('\r'),
      ];

  /// Replaces the upper area with [text], lines separated by `\r`.
  List<Uint8List> buildOriginalCommand(String text) =>
      _textFrames(0x0F, _heardSeq++, text);

  /// Replaces the lower area with [text], lines separated by `\r`.
  List<Uint8List> buildTranslatedCommand(String text) =>
      _textFrames(0x0D, _translatedSeq++, text);

  /// Wraps [text] at [width] characters and keeps the last [maxLines]
  /// lines, joined the way the screen expects them.
  static String layout(String text, {required int width}) {
    final lines = <String>[];
    final line = StringBuffer();
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (line.isNotEmpty && line.length + 1 + word.length > width) {
        lines.add(line.toString());
        line.clear();
      }
      if (line.isNotEmpty) line.write(' ');
      line.write(word);
    }
    if (line.isNotEmpty) lines.add(line.toString());
    final kept = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    return kept.join('\r');
  }

  /// `cmd seq count index newScreen posHi posLo` then the text. A new screen
  /// value of 0 redraws the whole area, so the position stays 0.
  static List<Uint8List> _textFrames(int command, int seq, String text) {
    final bytes = utf8.encode(text);
    final count = max(1, (bytes.length + _chunk - 1) ~/ _chunk);
    return [
      for (var i = 0; i < count; i++)
        Uint8List.fromList([
          command,
          seq & 0xFF,
          count,
          i,
          0x00,
          0x00,
          0x00,
          ...bytes.sublist(min(i * _chunk, bytes.length),
              min((i + 1) * _chunk, bytes.length)),
        ]),
    ];
  }
}
