import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Artwork written as text is easy to get subtly wrong — a row a character
/// short, a shape that is not symmetric. These catch that without anyone
/// having to look at a screen.
void main() {
  final drawings = <String, List<String>>{
    'glasses': PixelArtwork.glasses,
    'lens': PixelArtwork.lens,
    'caseClosed': PixelArtwork.caseClosed,
    'caseOpen': PixelArtwork.caseOpen,
    'sun': PixelArtwork.sun,
    'moon': PixelArtwork.moon,
    'note': PixelArtwork.note,
    'mic': PixelArtwork.mic,
    'grid': PixelArtwork.grid,
    'bell': PixelArtwork.bell,
    'lock': PixelArtwork.lock,
    'chat': PixelArtwork.chat,
  };

  group('Every drawing is well formed', () {
    test('rows are all the same length', () {
      drawings.forEach((name, rows) {
        final widths = rows.map((r) => r.length).toSet();
        expect(widths, hasLength(1),
            reason: '$name has rows of differing width: $widths');
      });
    });

    test('rows contain nothing but set and unset pixels', () {
      drawings.forEach((name, rows) {
        for (final row in rows) {
          expect(RegExp(r'^[#.]*$').hasMatch(row), isTrue,
              reason: '$name has an unexpected character in "$row"');
        }
      });
    });

    test('none is blank', () {
      drawings.forEach((name, rows) {
        expect(rows.any((r) => r.contains('#')), isTrue,
            reason: '$name draws nothing at all');
      });
    });
  });

  group('The glasses are symmetric', () {
    test('left and right halves mirror each other', () {
      // The two lenses are the same grid either side of the bridge, so any
      // asymmetry means a row was mistyped.
      for (final row in PixelArtwork.glasses) {
        expect(row, row.split('').reversed.join(),
            reason: 'this row is not symmetric: "$row"');
      }
    });
  });

  group('It renders', () {
    testWidgets('draws at the size it was asked for', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: PixelArt(rows: PixelArtwork.glasses, size: 24)),
        ),
      ));

      final size = tester.getSize(find.byType(PixelArt));
      expect(size.height, lessThanOrEqualTo(24));
      expect(size.width, greaterThan(0));
    });

    testWidgets('survives an empty drawing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: PixelArt(rows: [], size: 24))),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('never scales to less than one pixel per cell', (t) async {
      // A fractional scale is what turns crisp squares into a smear.
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: PixelArt(rows: PixelArtwork.glasses, size: 4)),
        ),
      ));
      final size = t.getSize(find.byType(PixelArt));
      expect(size.height, greaterThanOrEqualTo(PixelArtwork.glasses.length * 1.0));
    });
  });
}
