import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/case_battery.dart';

void main() {
  group('State change, the documented source', () {
    test('reads the percentage', () {
      final reading = CaseBatteryParser.fromStateChange([0xF5, 0x0F, 0x4B]);
      expect(reading?.percentage, 75);
      expect(reading?.source, CaseBatterySource.stateChange);
      expect(reading?.isConfirmed, isTrue);
    });

    test('accepts both ends of the range', () {
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x0F, 0x00])?.percentage,
          0);
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x0F, 0x64])?.percentage,
          100);
    });

    test('refuses a byte that cannot be a percentage', () {
      // Better nothing than a plausible-looking wrong number.
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x0F, 0x65]), isNull);
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x0F, 0xFF]), isNull);
    });

    test('ignores another subcommand on the same command', () {
      // 0xF5 also carries the touchpad events; those are not battery levels.
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x17, 0x01]), isNull);
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x18, 0x00]), isNull);
    });

    test('ignores a different command entirely', () {
      expect(CaseBatteryParser.fromStateChange([0x2C, 0x0F, 0x40]), isNull);
    });

    test('does not read past the end of a short frame', () {
      expect(CaseBatteryParser.fromStateChange([0xF5, 0x0F]), isNull);
      expect(CaseBatteryParser.fromStateChange([0xF5]), isNull);
      expect(CaseBatteryParser.fromStateChange([]), isNull);
    });
  });

  group('Polled reply, the suspected source', () {
    test('reads the candidate byte and says it is only a candidate', () {
      // The real frame from a capture: both temples at 100, case plugged in.
      final reading = CaseBatteryParser.fromPolledReply(
        [0x2C, 0x66, 0x64, 0x64, 0xEF, 0x86, 0x19],
      );
      expect(reading?.percentage, 100);
      expect(reading?.source, CaseBatterySource.polledCandidate);
      expect(reading?.isConfirmed, isFalse);
    });

    test('gives nothing when the byte cannot be a percentage', () {
      // If the hypothesis is wrong, this is what usually happens, and
      // returning null is what keeps a wrong number off the screen.
      expect(
        CaseBatteryParser.fromPolledReply([0x2C, 0x66, 0x64, 0xE6, 0x5D]),
        isNull,
      );
    });

    test('ignores a frame that is not a battery reply', () {
      expect(
        CaseBatteryParser.fromPolledReply([0x29, 0x65, 0x15, 0x01]),
        isNull,
      );
    });

    test('does not read past the end of a short frame', () {
      expect(CaseBatteryParser.fromPolledReply([0x2C, 0x66, 0x64]), isNull);
    });
  });
}
