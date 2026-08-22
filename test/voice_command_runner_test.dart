import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';
import 'package:g1_extended/services/voice_command_runner.dart';

void main() {
  group('Squeezing a forecast onto a lens', () {
    List<DailyForecast> week(int days) => [
          for (var i = 0; i < days; i++)
            DailyForecast(
              date: DateTime(2026, 8, 22 + i),
              weatherCode: 0,
              high: 24.4 + i,
              low: 13.6 + i,
            ),
        ];

    test('gives one short line per day', () {
      final line = VoiceCommandRunner.formatForecast(week(3));
      expect(line, contains('14/24°'));
      expect(line.split('   '), hasLength(3));
    });

    test('stops at what fits rather than running off the lens', () {
      final line = VoiceCommandRunner.formatForecast(week(7), maxDays: 5);
      expect(line.split('   '), hasLength(5));
    });

    test('rounds instead of showing decimals nobody reads', () {
      final line = VoiceCommandRunner.formatForecast(week(1));
      expect(line, isNot(contains('.')));
    });
  });

  group('Telling a number from a name', () {
    String? number(String text) => VoiceCommandRunner.phoneNumberIn(text);

    test('accepts a spoken number however it is punctuated', () {
      expect(number('06 12 34 56 78'), '0612345678');
      expect(number('+33 6 12 34 56 78'), '+33612345678');
    });

    test('treats a name as a name', () {
      expect(number('Simon Labbé'), isNull);
      expect(number('mum'), isNull);
    });

    test('rejects something too short to dial', () {
      expect(number('12345'), isNull);
    });

    test('does not mistake a name with a digit in it for a number', () {
      expect(number('Studio 54 reception desk'), isNull);
    });
  });
}
