import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/translate.dart';

/// The translation screen as the official Even app 1.6.5 drives it. See
/// docs/protocol/even-ai-transcribe-translate.md, section 7.
void main() {
  Translate frFromEn() => Translate(
        fromLanguage: TranslateLanguages.forCode('en'),
        toLanguage: TranslateLanguages.forCode('fr'),
      );

  test('start and stop carry the language pair', () {
    final t = frFromEn();
    expect(t.buildStartCommand(), [0x1C, 0x00, 0x02, 0x05]);
    expect(t.buildStopCommand(), [0x1C, 0x01, 0x02, 0x05]);
  });

  test('opening clears both areas with a lone carriage return', () {
    final frames = frFromEn().buildInitalScreenLoad();
    expect(frames, [
      [0x1C, 0x00, 0x02, 0x05],
      [0x0F, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x0D],
      [0x0D, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x0D],
    ]);
  });

  test('each area counts its own sequence', () {
    final t = frFromEn();
    t.buildOriginalCommand('a');
    expect(t.buildOriginalCommand('b').single[1], 1);
    expect(t.buildTranslatedCommand('c').single[1], 0);
  });

  test('a long text goes out in pieces of 193 bytes, numbered from 0', () {
    final frames = frFromEn().buildOriginalCommand('x' * 400);

    expect(frames.length, 3);
    expect([for (final f in frames) f[2]], [3, 3, 3]);
    expect([for (final f in frames) f[3]], [0, 1, 2]);
    expect([for (final f in frames) f.length - 7], [193, 193, 14]);
    expect(frames.first.sublist(4, 7), [0, 0, 0], reason: 'full redraw');
  });

  test('a caption is wrapped and only its last five lines are kept', () {
    final words = List.generate(30, (i) => 'w$i').join(' ');
    final laid = Translate.layout(words, width: 12);
    final lines = laid.split('\r');

    expect(lines.length, Translate.maxLines);
    expect(lines.every((l) => l.length <= 12), isTrue);
    expect(lines.last.endsWith('w29'), isTrue);
    expect(utf8.encode(laid).contains(0x0A), isFalse, reason: 'no \\n');
  });

  test('the glasses know twenty-five languages, English otherwise', () {
    expect(TranslateLanguages.forCode('de'), 6);
    expect(TranslateLanguages.forCode('ja'), 3);
    expect(TranslateLanguages.forCode('pt'), 22);
    expect(TranslateLanguages.forCode('xx'), TranslateLanguages.ENGLISH);
  });
}
