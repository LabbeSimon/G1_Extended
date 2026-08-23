import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/glass.dart';

/// The reconnect loop runs for as long as the app does, so the shape of its
/// backoff is a battery decision rather than a politeness one.
///
/// It is keyed on how long the glasses have been absent rather than on how
/// many attempts have been made, because that is what predicts whether the
/// next one will succeed: a second of interference resolves at once, a pair
/// in the case will not be back for hours.
void main() {
  int wait(Duration absent) => Glass.reconnectDelayFor(absent).inSeconds;

  /// Attempts made over [window], following the schedule.
  int attemptsOver(Duration window) {
    var elapsed = Duration.zero;
    var attempts = 0;
    while (elapsed < window) {
      elapsed += Glass.reconnectDelayFor(elapsed);
      attempts++;
    }
    return attempts;
  }

  group('Coming straight back is invisible', () {
    test('the first half minute is checked every two seconds', () {
      expect(wait(Duration.zero), 2);
      expect(wait(const Duration(seconds: 20)), 2);
    });

    test('stepping out of range and back costs seconds, not minutes', () {
      expect(attemptsOver(const Duration(seconds: 30)),
          greaterThanOrEqualTo(10));
    });
  });

  group('A long absence stops costing anything', () {
    test('the interval only ever grows', () {
      var previous = 0;
      for (final minutes in [0, 1, 3, 15, 45, 90, 600]) {
        final now = wait(Duration(minutes: minutes));
        expect(now, greaterThanOrEqualTo(previous),
            reason: 'the wait shrank at $minutes minutes');
        previous = now;
      }
    });

    test('the first hour costs far less than the old flat schedule', () {
      // The previous version polled every thirty seconds without end: 120 an
      // hour, and that was one of three loops running at once.
      expect(attemptsOver(const Duration(hours: 1)), lessThan(120));
    });

    test('an overnight absence is quiet', () {
      // Eight hours in a drawer used to mean about a thousand attempts from
      // this loop alone.
      expect(attemptsOver(const Duration(hours: 8)), lessThan(200));
    });

    test('but it never stops entirely', () {
      // Giving up is what made the previous version indistinguishable from
      // having no reconnection at all.
      expect(wait(const Duration(days: 7)), greaterThan(0));
    });
  });

  group('The schedule stays within sane bounds', () {
    test('never tighter than two seconds', () {
      for (final m in [0, 1, 5, 30, 120, 1440]) {
        expect(wait(Duration(minutes: m)), greaterThanOrEqualTo(2));
      }
    });

    test('never looser than five minutes', () {
      // Anything longer and picking the glasses up would feel broken, even
      // with the foreground nudge.
      for (final m in [0, 1, 5, 30, 120, 1440]) {
        expect(wait(Duration(minutes: m)), lessThanOrEqualTo(300));
      }
    });

    test('a negative duration does not produce a nonsense wait', () {
      expect(wait(const Duration(seconds: -5)), 2);
    });
  });
}
