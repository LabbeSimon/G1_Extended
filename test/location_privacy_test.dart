import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';

/// The weather forecast is the only request that carries anything personal.
/// These tests pin down how much precision actually leaves the device.
void main() {
  group('Coordinate coarsening before the weather request', () {
    test('keeps two decimal places', () {
      expect(OpenMeteoWeatherService.coarsen(48.8566123), 48.86);
      expect(OpenMeteoWeatherService.coarsen(2.3522456), 2.35);
    });

    test('handles southern and western hemispheres', () {
      expect(OpenMeteoWeatherService.coarsen(-33.868821), -33.87);
      expect(OpenMeteoWeatherService.coarsen(-70.123456), -70.12);
    });

    test('rounds rather than truncates', () {
      expect(OpenMeteoWeatherService.coarsen(10.999), 11.0);
      expect(OpenMeteoWeatherService.coarsen(-10.999), -11.0);
    });

    test('leaves an already coarse coordinate untouched', () {
      expect(OpenMeteoWeatherService.coarsen(45.0), 45.0);
      expect(OpenMeteoWeatherService.coarsen(0.0), 0.0);
    });

    test('never emits more than two decimals, whatever the input', () {
      const samples = [
        51.5073509, -0.1277583, 35.6894875, 139.6917064, 90.0, -180.0,
      ];
      for (final value in samples) {
        final coarse = OpenMeteoWeatherService.coarsen(value);
        final decimals = coarse.toString().split('.').last;
        expect(decimals.length, lessThanOrEqualTo(2),
            reason: '$value became $coarse');
      }
    });

    test('discards enough precision to lose a street address', () {
      // Two points ~150 m apart must collapse onto the same forecast grid
      // point, so the request cannot distinguish one building from another.
      expect(
        OpenMeteoWeatherService.coarsen(48.8566),
        OpenMeteoWeatherService.coarsen(48.8570),
      );
    });
  });
}
