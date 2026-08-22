import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';

void main() {
  group('Brightness', () {
    test('builds a set command inside the protocol range', () {
      final command =
          const BrightnessSetting(level: 0x2A, auto: true).buildSetCommand();
      expect(command, [0x01, 0x2A, 0x01]);
    });

    test('clamps a level above the hardware maximum', () {
      final command =
          const BrightnessSetting(level: 200, auto: false).buildSetCommand();
      expect(command[1], BrightnessSetting.maxLevel);
    });

    test('converts a slider fraction to a protocol level', () {
      final setting = BrightnessSetting.fromFraction(0.5, auto: false);
      expect(setting.level, (BrightnessSetting.maxLevel * 0.5).round());
    });

    test('parses a get response', () {
      final setting = BrightnessSetting.parseResponse([0x29, 0x65, 0x15, 0x01]);
      expect(setting?.level, 0x15);
      expect(setting?.auto, isTrue);
    });

    test('rejects a response for a different command', () {
      expect(BrightnessSetting.parseResponse([0x2B, 0x65, 0x15, 0x01]), isNull);
    });
  });

  group('HeadUpAngle', () {
    test('builds a set command with the trailing level byte', () {
      expect(const HeadUpAngle(30).buildSetCommand(), [0x0B, 30, 0x01]);
    });

    test('clamps beyond 60 degrees', () {
      expect(const HeadUpAngle(200).buildSetCommand()[1],
          HeadUpAngle.maxDegrees);
    });

    test('parses the angle out of a get response', () {
      expect(HeadUpAngle.parseResponse([0x32, 0x6d, 0x0f, 0x1E])?.degrees, 30);
    });
  });

  group('DisplayPosition', () {
    test('preview and commit differ only by the preview byte', () {
      const position = DisplayPosition(height: 4, depth: 5);
      final preview = position.buildSetCommand(sequence: 7, preview: true);
      final commit = position.buildSetCommand(sequence: 7, preview: false);

      expect(preview[5], 0x01);
      expect(commit[5], 0x00);
      expect(preview.sublist(6), commit.sublist(6));
    });

    test('wraps the sequence number into a single byte', () {
      final command = const DisplayPosition(height: 1, depth: 1)
          .buildSetCommand(sequence: 300, preview: false);
      expect(command[3], 300 & 0xFF);
    });

    test('clamps height and depth to their documented ranges', () {
      final command = const DisplayPosition(height: 99, depth: 99)
          .buildSetCommand(sequence: 0, preview: false);
      expect(command[6], DisplayPosition.maxHeight);
      expect(command[7], DisplayPosition.maxDepth);
    });

    test('parses a get response', () {
      final position = DisplayPosition.parseResponse([0x3B, 0xC9, 0x03, 0x06]);
      expect(position?.height, 3);
      expect(position?.depth, 6);
    });

    test('rejects a failure response', () {
      expect(DisplayPosition.parseResponse([0x3B, 0xCA, 0x03, 0x06]), isNull);
    });
  });

  group('SilentMode', () {
    test('uses the documented on and off subcommands', () {
      expect(SilentMode.buildSetCommand(true), [0x03, 0x0C]);
      expect(SilentMode.buildSetCommand(false), [0x03, 0x0A]);
    });

    test('parses both states from a get response', () {
      expect(SilentMode.parseResponse([0x2B, 0x69, 0x0C, 0x06]), isTrue);
      expect(SilentMode.parseResponse([0x2B, 0x69, 0x0A, 0x08]), isFalse);
    });
  });

  group('WearDetection', () {
    test('builds enable and disable commands', () {
      expect(WearDetection.buildSetCommand(true), [0x27, 0x01]);
      expect(WearDetection.buildSetCommand(false), [0x27, 0x00]);
    });

    test('parses a get response', () {
      expect(WearDetection.parseResponse([0x3A, 0xC9, 0x01]), isTrue);
    });
  });

  group('DeviceInfo', () {
    test('reads the ASCII build string out of a binary reply', () {
      final payload = <int>[
        0x02, 0x03, 0x20, 0xcf, 0x00, 0xcb,
        ...'net build time: 2024-12-28, ver 1.4.5'.codeUnits,
        0x00, 0x00, 0x00,
      ];
      expect(DeviceInfo.parseFirmware(payload), contains('ver 1.4.5'));
    });

    test('decodes uptime as little endian seconds', () {
      expect(
        DeviceInfo.parseUptime([0x37, 0x49, 0x1a, 0x00, 0x00]),
        const Duration(seconds: 0x1a49),
      );
    });

    test('hard reset is the documented two byte command', () {
      expect(DeviceInfo.buildHardResetCommand(), [0x23, 0x72]);
    });
  });

  group('DashboardLayoutCommand', () {
    test('reproduces the byte sequence the original code hard-coded', () {
      // Legacy constants were [0x06,0x07,0x00] + [seq,0x06,mode,pane].
      expect(
        DashboardLayoutCommand.build(
          mode: DashboardMode.full,
          pane: DashboardPane.notes,
          sequence: 0x08,
        ),
        [0x06, 0x07, 0x00, 0x08, 0x06, 0x00, 0x00],
      );
      expect(
        DashboardLayoutCommand.build(
          mode: DashboardMode.dual,
          pane: DashboardPane.notes,
          sequence: 0x1E,
        ),
        [0x06, 0x07, 0x00, 0x1E, 0x06, 0x01, 0x00],
      );
      expect(
        DashboardLayoutCommand.build(
          mode: DashboardMode.minimal,
          pane: DashboardPane.notes,
          sequence: 0x31,
        ),
        [0x06, 0x07, 0x00, 0x31, 0x06, 0x02, 0x05],
      );
    });

    test('declares a length matching the packet it produces', () {
      final command = DashboardLayoutCommand.build(
        mode: DashboardMode.dual,
        pane: DashboardPane.calendar,
        sequence: 1,
      );
      expect(command[1], command.length);
    });

    test('forces an empty pane on minimal, which has no room for one', () {
      final command = DashboardLayoutCommand.build(
        mode: DashboardMode.minimal,
        pane: DashboardPane.calendar,
        sequence: 1,
      );
      expect(command[6], DashboardPane.empty.id);
    });

    test('wraps the sequence into a byte', () {
      final command = DashboardLayoutCommand.build(
        mode: DashboardMode.full,
        pane: DashboardPane.news,
        sequence: 260,
      );
      expect(command[3], 260 & 0xFF);
    });
  });

  group('DebugMode', () {
    test('is a single byte either way', () {
      expect(DebugMode.buildSetCommand(true), [0xF4, 0x01]);
      expect(DebugMode.buildSetCommand(false), [0xF4, 0x00]);
    });
  });
}
