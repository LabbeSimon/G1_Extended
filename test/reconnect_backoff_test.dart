import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/glass.dart';

/// The reconnection loop now runs for as long as the app does, which makes
/// the shape of its backoff something that has to be right rather than
/// something that only delays giving up.
void main() {
  int seconds(int attempt) => Glass.reconnectDelayFor(attempt).inSeconds;

  test('the first retry is quick', () {
    // Most disconnections are a moment of interference, not the glasses
    // going away. Waiting long on the first attempt is felt every time.
    expect(seconds(1), 2);
  });

  test('it backs off', () {
    expect(seconds(2), greaterThan(seconds(1)));
    expect(seconds(3), greaterThan(seconds(2)));
    expect(seconds(4), greaterThan(seconds(3)));
  });

  test('it never waits longer than thirty seconds', () {
    // Without a ceiling, glasses put down for an hour would be checked on
    // once an hour. Putting them back on has to be noticed promptly.
    for (var attempt = 1; attempt <= 10000; attempt++) {
      expect(seconds(attempt), lessThanOrEqualTo(30),
          reason: 'attempt $attempt waits ${seconds(attempt)}s');
    }
  });

  test('it never waits less than two seconds', () {
    // A tight loop of failing BLE connects is a battery drain with nothing
    // to show for it.
    for (var attempt = 1; attempt <= 10000; attempt++) {
      expect(seconds(attempt), greaterThanOrEqualTo(2),
          reason: 'attempt $attempt waits ${seconds(attempt)}s');
    }
  });

  test('the ceiling is reached quickly, then held', () {
    // Reaching thirty seconds should take under a minute of real time, so a
    // long absence settles into a steady poll rather than a long ramp.
    expect(seconds(5), 30);
    expect(seconds(50), 30);
  });

  test('nonsense input does not produce a nonsense wait', () {
    expect(seconds(0), 2);
    expect(seconds(-1), 2);
  });

  test('the first minute holds several attempts', () {
    // Someone stepping out of range and back should reconnect within a few
    // seconds, not after the ramp has finished.
    var elapsed = 0;
    var attempts = 0;
    while (elapsed < 60) {
      attempts++;
      elapsed += seconds(attempts);
    }
    expect(attempts, greaterThanOrEqualTo(4),
        reason: 'only $attempts attempts in the first minute');
  });
}
