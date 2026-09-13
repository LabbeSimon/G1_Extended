import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/lens_framebuffer.dart';
import 'package:g1_extended/models/g1/text.dart';
import 'package:g1_extended/services/lens_emulator.dart';
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

  test('five lines of the panel type fit the lens, six do not', () {
    // The firmware composes five lines per screen. The type here is sized to
    // agree with that, and this is what says so out loud: change the size or
    // the leading and this test is where it shows up.
    final lineHeight = LensPanel.fontSize * LensPanel.lineHeight;

    expect(lineHeight * 5, lessThanOrEqualTo(LensFramebuffer.height.toDouble()));
    expect(lineHeight * 6, greaterThan(LensFramebuffer.height.toDouble()));
  });
}
