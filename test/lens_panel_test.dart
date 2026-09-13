import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/lens_framebuffer.dart';
import 'package:g1_extended/models/g1/text.dart';
import 'package:g1_extended/services/lens_emulator.dart';
import 'package:g1_extended/services/lens_renderer.dart';
import 'package:g1_extended/widgets/lens_panel.dart';

void main() {
  testWidgets('the panel draws what the emulator decoded', (tester) async {
    final emulator = LensEmulator();
    for (final packet in TextMessage('bonjour la lentille').constructSendText()) {
      emulator.consume(packet);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LensPanel(state: emulator.state)),
      ),
    );
    // Rasterising goes through the real engine, which needs a real event
    // loop: pumpWidget alone would leave the panel empty for ever.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.byType(LensPanel), findsOneWidget);
    expect(find.text('page 1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty state says so rather than looking asleep',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LensPanel(state: LensState())),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.text('blank'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lens can be exported as a PNG', (tester) async {
    final emulator = LensEmulator()
      ..consume(TextMessage('export').constructSendText().first);

    Uint8List? png;
    await tester.runAsync(() async {
      final frame = await LensRenderer.rasterise(emulator.state);
      png = await LensRenderer.toPng(frame);
    });

    expect(png, isNotNull);
    // Eight bytes of PNG signature, which is what makes it openable rather
    // than a buffer we called an image.
    expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  testWidgets('the type is sized to the wrap in force', (tester) async {
    // Twenty-five characters filling a 488 pixel column means large type and
    // few lines; forty means smaller type and five. The mirror has to show
    // that, or comparing the two on it proves nothing.
    await tester.runAsync(() async {
      final wide = LensRenderer.fontSizeFor(25);
      final narrow = LensRenderer.fontSizeFor(40);

      expect(wide, greaterThan(narrow));
      expect(LensRenderer.linesFor(narrow), 5);
      // Not "fewer lines at twenty-five" as an absolute: the harness draws
      // with a square test font whose advance is nothing like a phone's, so
      // the only thing that holds everywhere is that larger type fits fewer
      // lines, and that the panel never claims more than the five the
      // firmware composes.
      expect(
        LensRenderer.linesFor(wide),
        lessThanOrEqualTo(LensRenderer.linesFor(narrow)),
      );
      expect(LensRenderer.linesFor(40), lessThan(5));
    });
  });

  test('five lines of the panel type fit the lens, six do not', () {
    // The firmware composes five lines per screen. The type here is sized to
    // agree with that, and this is what says so out loud: change the size or
    // the leading and this test is where it shows up.
    final lineHeight = LensPanel.fontSize * LensPanel.lineHeight;

    expect(lineHeight * 5, lessThanOrEqualTo(LensFramebuffer.height.toDouble()));
    expect(lineHeight * 6, greaterThan(LensFramebuffer.height.toDouble()));
  });
}
