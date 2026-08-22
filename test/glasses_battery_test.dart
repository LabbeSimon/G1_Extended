import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';

/// Two temples discharge together, so two gauges usually repeat the same
/// number twice. They only earn their own line when they have really drifted.
void main() {
  test('stays as one reading while the sides agree', () {
    expect(GlassesBattery.shouldSplit(80, 78), isFalse);
    expect(GlassesBattery.shouldSplit(80, 80), isFalse);
    expect(GlassesBattery.shouldSplit(45, 38), isFalse);
  });

  test('splits once the gap is worth knowing about', () {
    expect(GlassesBattery.shouldSplit(80, 70), isTrue);
    expect(GlassesBattery.shouldSplit(20, 95), isTrue);
    expect(GlassesBattery.shouldSplit(30, 55), isTrue);
  });

  test('never splits when a side has not reported', () {
    expect(GlassesBattery.shouldSplit(null, 70), isFalse);
    expect(GlassesBattery.shouldSplit(80, null), isFalse);
    expect(GlassesBattery.shouldSplit(null, null), isFalse);
  });

  test('shows the side that runs out first', () {
    expect(GlassesBattery.lowest(80, 62), 62);
    expect(GlassesBattery.lowest(40, 91), 40);
    expect(GlassesBattery.lowest(50, 50), 50);
  });

  test('falls back to whichever side reported', () {
    expect(GlassesBattery.lowest(null, 70), 70);
    expect(GlassesBattery.lowest(55, null), 55);
    expect(GlassesBattery.lowest(null, null), isNull);
  });

  test('the split threshold is symmetric', () {
    expect(
      GlassesBattery.shouldSplit(90, 80),
      GlassesBattery.shouldSplit(80, 90),
    );
  });
}
