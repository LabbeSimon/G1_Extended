import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:g1_extended/services/world_clocks.dart';

/// The clock lines as they go onto the lens. Zones, not offsets, so summer
/// time is right on both sides of every date — that correctness is the whole
/// reason the timezone database is aboard.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  const tokyo = WorldClock(label: 'Tokyo', zoneId: 'Asia/Tokyo');
  const paris = WorldClock(label: 'Paris', zoneId: 'Europe/Paris');
  const la = WorldClock(label: 'LA', zoneId: 'America/Los_Angeles');

  group('The line itself', () {
    test('carries the label and a padded time', () {
      // Noon UTC in August: Tokyo is UTC+9.
      final noon = DateTime.utc(2026, 8, 23, 12, 0);
      expect(WorldClocksService.formatLine(tokyo, noon), 'Tokyo 21:00');
    });

    test('marks tomorrow, because that is the surprising part', () {
      // 16:30 UTC: Tokyo is already past midnight.
      final evening = DateTime.utc(2026, 8, 23, 16, 30);
      expect(WorldClocksService.formatLine(tokyo, evening), 'Tokyo 01:30 +1');
    });

    test('marks yesterday the other way', () {
      // 02:00 UTC: Los Angeles is still on the previous date.
      final early = DateTime.utc(2026, 8, 23, 2, 0);
      expect(WorldClocksService.formatLine(la, early), 'LA 19:00 -1');
    });
  });

  group('Summer time is honoured, which an offset cannot do', () {
    test('Paris is UTC+2 in August', () {
      final noon = DateTime.utc(2026, 8, 23, 12, 0);
      expect(WorldClocksService.formatLine(paris, noon), 'Paris 14:00');
    });

    test('and UTC+1 in January, from the same configuration', () {
      final noon = DateTime.utc(2026, 1, 23, 12, 0);
      expect(WorldClocksService.formatLine(paris, noon), 'Paris 13:00');
    });
  });

  group('Bad data degrades to absence, not to a wrong time', () {
    test('an unknown zone produces no line at all', () {
      const broken = WorldClock(label: 'Nulle-part', zoneId: 'Mars/Olympus');
      expect(
        WorldClocksService.formatLine(broken, DateTime.utc(2026, 8, 23)),
        isNull,
      );
    });

    test('a damaged stored entry is dropped when read back', () {
      expect(WorldClock.fromMap('not a map'), isNull);
      expect(WorldClock.fromMap({'label': 'x'}), isNull);
    });
  });
}
