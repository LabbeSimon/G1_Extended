import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/heart_rate.dart';

/// Frames built by hand against the Bluetooth spec, one per shape the flag
/// byte allows. The eight-versus-sixteen-bit split is the classic trap: a
/// parser that assumes eight bits works on every test bench and fails on
/// the first sensor that reports over 255 — or pads to sixteen regardless.
void main() {
  group('The two rate widths', () {
    test('eight-bit, the common case', () {
      final m = HeartRateMeasurement.parse([0x00, 72]);
      expect(m!.bpm, 72);
      expect(m.contactDetected, isNull);
      expect(m.energyKilojoules, isNull);
      expect(m.rrIntervals, isEmpty);
    });

    test('sixteen-bit, little-endian', () {
      final m = HeartRateMeasurement.parse([0x01, 0x2C, 0x01]);
      expect(m!.bpm, 300);
    });

    test('sixteen-bit is honoured even for small values', () {
      // A sensor may pad: flag says 16-bit, value fits in 8.
      final m = HeartRateMeasurement.parse([0x01, 68, 0x00]);
      expect(m!.bpm, 68);
    });
  });

  group('Sensor contact', () {
    test('unsupported reads as unknown, not as "no contact"', () {
      final m = HeartRateMeasurement.parse([0x00, 70]);
      expect(m!.contactDetected, isNull);
    });

    test('supported and detected', () {
      final m = HeartRateMeasurement.parse([0x06, 70]);
      expect(m!.contactDetected, isTrue);
    });

    test('supported and lost — the strap slipped', () {
      final m = HeartRateMeasurement.parse([0x04, 70]);
      expect(m!.contactDetected, isFalse);
    });
  });

  group('Optional fields stack in spec order', () {
    test('energy expended', () {
      final m = HeartRateMeasurement.parse([0x08, 80, 0x10, 0x27]);
      expect(m!.bpm, 80);
      expect(m.energyKilojoules, 10000);
    });

    test('rr intervals, in 1/1024ths of a second', () {
      final m = HeartRateMeasurement.parse([0x10, 80, 0x00, 0x04, 0x00, 0x02]);
      expect(m!.rrIntervals, [1.0, 0.5]);
    });

    test('energy and rr together, energy first as the spec orders', () {
      final m = HeartRateMeasurement.parse(
          [0x18, 80, 0x64, 0x00, 0x00, 0x04]);
      expect(m!.energyKilojoules, 100);
      expect(m.rrIntervals, [1.0]);
    });
  });

  group('Truncated frames are refused, not misread', () {
    test('too short to exist', () {
      expect(HeartRateMeasurement.parse([]), isNull);
      expect(HeartRateMeasurement.parse([0x00]), isNull);
    });

    test('flags promising sixteen bits with only eight present', () {
      expect(HeartRateMeasurement.parse([0x01, 72]), isNull);
    });

    test('flags promising energy that is not there', () {
      expect(HeartRateMeasurement.parse([0x08, 80]), isNull);
      expect(HeartRateMeasurement.parse([0x08, 80, 0x10]), isNull);
    });

    test('an odd trailing rr byte is dropped, not invented', () {
      final m = HeartRateMeasurement.parse([0x10, 80, 0x00, 0x04, 0x99]);
      expect(m!.rrIntervals, [1.0]);
    });
  });
}
