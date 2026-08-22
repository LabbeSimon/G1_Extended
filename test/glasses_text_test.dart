import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/utils/glasses_text.dart';

/// Even Realities list Russian, Arabic, Hindi, Bengali and traditional
/// Chinese as languages the display cannot show. Sending them anyway produces
/// blank boxes on the lens, which reads as a broken app.
void main() {
  test('passes what the display carries', () {
    expect(GlassesText.canDisplay('Turn right onto Rue de la Paix'), isTrue);
    expect(GlassesText.canDisplay('21°C · 78%'), isTrue);
    expect(GlassesText.canDisplay('Café, naïve, œuf'), isTrue);
  });

  test('passes the CJK the display does carry', () {
    // Japanese, Korean and simplified Chinese are listed without a caveat.
    expect(GlassesText.canDisplay('こんにちは'), isTrue);
    expect(GlassesText.canDisplay('안녕하세요'), isTrue);
    expect(GlassesText.canDisplay('你好'), isTrue);
  });

  test('spots the scripts it cannot draw', () {
    expect(GlassesText.unsupportedScripts('Привет'), ['Cyrillic']);
    expect(GlassesText.unsupportedScripts('مرحبا'), ['Arabic']);
    expect(GlassesText.unsupportedScripts('नमस्ते'), ['Devanagari']);
    expect(GlassesText.unsupportedScripts('হ্যালো'), ['Bengali']);
  });

  test('names every script in a mixed line, once each', () {
    final found = GlassesText.unsupportedScripts('Hello Привет مرحبا Привет');
    expect(found, ['Arabic', 'Cyrillic']);
  });

  test('says so rather than sending boxes to the lens', () {
    expect(GlassesText.prepare('Привет'), contains('cannot show'));
    expect(GlassesText.prepare('Привет'), contains('Cyrillic'));
  });

  test('leaves displayable text untouched', () {
    const line = 'Turn right in 200 m';
    expect(GlassesText.prepare(line), line);
  });

  test('handles an empty line', () {
    expect(GlassesText.canDisplay(''), isTrue);
    expect(GlassesText.prepare(''), '');
  });
}
