import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/speedometer_service.dart';

/// What ends up on the lens, in the three shapes the settings allow.
void main() {
  const kmh = SpeedUnit.kmh;

  group('Rounding', () {
    test('whole numbers by default', () {
      expect(SpeedometerService.format(7.6, kmh), '27 ${kmh.label}');
    });

    test('a tenth when asked', () {
      expect(SpeedometerService.format(7.6, kmh, decimals: true),
          '27.4 ${kmh.label}');
    });

    test('standing still reads zero, not a stale number', () {
      expect(SpeedometerService.format(0, kmh), '0 ${kmh.label}');
      expect(
          SpeedometerService.format(0, kmh, decimals: true), '0.0 ${kmh.label}');
    });

    test('a bad reading produces nothing rather than a wrong number', () {
      expect(SpeedometerService.format(double.nan, kmh), isNull);
      expect(SpeedometerService.format(-1, kmh), isNull);
    });
  });

  group('Decimal comma', () {
    test('replaces the point', () {
      expect(
        SpeedometerService.format(7.6, kmh, decimals: true, decimalComma: true),
        '27,4 ${kmh.label}',
      );
    });

    test('changes nothing when there is no decimal', () {
      expect(SpeedometerService.format(7.6, kmh, decimalComma: true),
          '27 ${kmh.label}');
    });

    test('applies to zero as well', () {
      expect(
        SpeedometerService.format(0, kmh, decimals: true, decimalComma: true),
        '0,0 ${kmh.label}',
      );
    });
  });

  group('The clock', () {
    test('is padded to two digits on both sides', () {
      final text = SpeedometerService.withClock(
        '27 km/h',
        DateTime(2026, 1, 2, 9, 5),
      );
      expect(text, contains('09:05'));
    });

    test('keeps the speed first, where the eye lands', () {
      final text = SpeedometerService.withClock(
        '27 km/h',
        DateTime(2026, 1, 2, 23, 59),
      );
      expect(text.startsWith('27 km/h'), isTrue);
      expect(text, endsWith('23:59'));
    });

    test('stays inside a sensible width for the lens', () {
      // 640 by 200 at the dashboard font leaves little room; anything much
      // past twenty characters starts wrapping.
      final text = SpeedometerService.withClock(
        SpeedometerService.format(30, SpeedUnit.kmh, decimals: true)!,
        DateTime(2026, 1, 2, 23, 59),
      );
      expect(text.length, lessThanOrEqualTo(22), reason: text);
    });
  });
}
