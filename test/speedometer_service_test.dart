import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/speedometer_service.dart';

/// GPS reports speed in metres per second, and reports noise when the phone is
/// still. These pin down what actually reaches the lens.
void main() {
  String? kmh(double mps) =>
      SpeedometerService.format(mps, SpeedUnit.kmh);
  String? mph(double mps) =>
      SpeedometerService.format(mps, SpeedUnit.mph);

  test('converts metres per second to km/h', () {
    expect(kmh(10), '36 km/h');
    expect(kmh(25), '90 km/h');
  });

  test('converts to mph when asked', () {
    expect(mph(10), '22 mph');
    expect(mph(0), '0 mph');
  });

  test('reads zero rather than jittering when the phone is still', () {
    // A parked phone reports small non-zero speeds from GPS noise; rounding
    // them would show 1 km/h, 2 km/h, 1 km/h on a stationary bike.
    expect(kmh(0.1), '0 km/h');
    expect(kmh(0.4), '0 km/h');
  });

  test('shows a real crawl once it is above the noise floor', () {
    expect(kmh(1.0), '4 km/h');
  });

  test('rounds to whole units', () {
    expect(kmh(10.1), '36 km/h');
    expect(kmh(10.9), '39 km/h');
  });

  test('gives nothing for a reading that cannot be true', () {
    expect(kmh(-1), isNull);
    expect(kmh(double.nan), isNull);
  });
}
