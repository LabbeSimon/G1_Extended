import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('The gauge actually draws something', () {
    testWidgets('shows the percentage', (tester) async {
      await tester.pumpWidget(wrap(const BatteryGauge(percentage: 78)));
      expect(find.text('78%'), findsOneWidget);
    });

    testWidgets('shows dashes rather than nothing when unknown', (t) async {
      await t.pumpWidget(wrap(const BatteryGauge(percentage: null)));
      expect(find.text('--%'), findsOneWidget);
    });

    testWidgets('takes a non-zero amount of space', (tester) async {
      // A gauge that lays out to nothing is invisible without being absent,
      // which is the hardest kind of missing to notice.
      await tester.pumpWidget(wrap(const BatteryGauge(percentage: 50)));
      final size = tester.getSize(find.byType(BatteryGauge));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    testWidgets('shows a side label when given one', (tester) async {
      await tester.pumpWidget(wrap(const BatteryGauge(
        percentage: 30,
        label: 'L',
      )));
      expect(find.text('L'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
    });
  });

  group('The pair', () {
    testWidgets('shows one reading when the sides agree', (tester) async {
      await tester.pumpWidget(wrap(const GlassesBattery(left: 80, right: 78)));
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('80%'), findsNothing);
      expect(find.text('L'), findsNothing);
    });

    testWidgets('splits when the sides diverge', (tester) async {
      await tester.pumpWidget(wrap(const GlassesBattery(left: 90, right: 40)));
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('still renders when nothing has reported', (tester) async {
      // The case that matters: connected but no reading yet must show
      // something, not collapse to an empty box.
      await tester.pumpWidget(
          wrap(const GlassesBattery(left: null, right: null)));
      expect(find.text('--%'), findsOneWidget);
    });

    testWidgets('renders inside a constrained row like the real screens',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 160,
          child: IntrinsicHeight(
            child: Row(
              children: const [
                Expanded(child: GlassesBattery(left: 65, right: 64)),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('64%'), findsOneWidget);
    });
  });
}
