import 'dart:typed_data';

/// Command bytes for the G1 settings surface.
///
/// Values and ranges come from `Even Realities G1 BLE Protocol.txt`.
/// Everything here is a pure builder or parser: no I/O, so it is testable
/// without a pair of glasses on the desk.
abstract final class SettingsCommands {
  static const int dashboard = 0x06;
  static const int setDebugMode = 0xF4;

  static const int setBrightness = 0x01;
  static const int getBrightness = 0x29;

  static const int setSilentMode = 0x03;
  static const int getSilentMode = 0x2B;

  static const int setHeadUpAngle = 0x0B;
  static const int getHeadUpAngle = 0x32;

  static const int setDisplayPosition = 0x26;
  static const int getDisplayPosition = 0x3B;

  static const int setWearDetection = 0x27;
  static const int getWearDetection = 0x3A;

  static const int clearScreen = 0x18;

  /// Settings and flow control, with a subcommand in byte 3.
  static const int flow = 0x10;

  /// Sent as part of the calibration handshake. Purpose unclear beyond that.
  static const int calibrationPrelude = 0x39;

  /// Documented as "Send Dashboard Lock", and used by calibration to stop
  /// the dashboard redrawing over the prompt.
  static const int dashboardLock = 0x50;
  static const int deviceInfo = 0x23;
  static const int timeSinceBoot = 0x37;

  static const int responseSuccess = 0xC9;
  static const int responseFailure = 0xCA;
}

/// Screen brightness, and whether the glasses adjust it themselves.
class BrightnessSetting {
  /// Raw protocol range. 0x2A is the brightest the hardware accepts.
  static const int maxLevel = 0x2A;

  final int level;
  final bool auto;

  const BrightnessSetting({required this.level, required this.auto});

  /// Brightness as a 0.0 - 1.0 fraction, for sliders.
  double get fraction => level / maxLevel;

  static BrightnessSetting fromFraction(double value, {required bool auto}) =>
      BrightnessSetting(
        level: (value.clamp(0.0, 1.0) * maxLevel).round(),
        auto: auto,
      );

  /// `01 <level> <auto>` — send to the right arm.
  Uint8List buildSetCommand() => Uint8List.fromList([
        SettingsCommands.setBrightness,
        level.clamp(0, maxLevel),
        auto ? 0x01 : 0x00,
      ]);

  static Uint8List buildGetCommand() =>
      Uint8List.fromList([SettingsCommands.getBrightness]);

  /// Response is `29 65 <level> <auto>`.
  static BrightnessSetting? parseResponse(List<int> data) {
    if (data.length < 4 || data[0] != SettingsCommands.getBrightness) {
      return null;
    }
    return BrightnessSetting(
      level: data[2].clamp(0, maxLevel),
      auto: data[3] == 0x01,
    );
  }
}

/// The angle you have to look up before the display wakes.
class HeadUpAngle {
  /// Degrees. The protocol accepts 0x00 - 0x3C.
  static const int maxDegrees = 0x3C;

  final int degrees;

  const HeadUpAngle(this.degrees);

  /// `0B <angle> 01` — send to the right arm.
  Uint8List buildSetCommand() => Uint8List.fromList([
        SettingsCommands.setHeadUpAngle,
        degrees.clamp(0, maxDegrees),
        0x01,
      ]);

  static Uint8List buildGetCommand() =>
      Uint8List.fromList([SettingsCommands.getHeadUpAngle]);

  /// Response is `32 6d 0f <angle> ...`.
  static HeadUpAngle? parseResponse(List<int> data) {
    if (data.length < 4 || data[0] != SettingsCommands.getHeadUpAngle) {
      return null;
    }
    return HeadUpAngle(data[3].clamp(0, maxDegrees));
  }
}

/// Where the text sits in the lens: how high, and how far away it looks.
class DisplayPosition {
  static const int minHeight = 0;
  static const int maxHeight = 8;
  static const int minDepth = 1;
  static const int maxDepth = 9;

  final int height;
  final int depth;

  const DisplayPosition({required this.height, required this.depth});

  /// `26 08 00 <seq> 02 <preview> <height> <depth>` — right arm.
  ///
  /// The glasses reject the setting unless a [preview] command comes first:
  /// send `preview: true`, let the wearer look, then send `preview: false`
  /// to commit. Without the commit the display stays on permanently.
  Uint8List buildSetCommand({required int sequence, required bool preview}) =>
      Uint8List.fromList([
        SettingsCommands.setDisplayPosition,
        0x08,
        0x00,
        sequence & 0xFF,
        0x02,
        preview ? 0x01 : 0x00,
        height.clamp(minHeight, maxHeight),
        depth.clamp(minDepth, maxDepth),
      ]);

  static Uint8List buildGetCommand() =>
      Uint8List.fromList([SettingsCommands.getDisplayPosition]);

  /// Response is `3B C9 <height> <depth>`.
  static DisplayPosition? parseResponse(List<int> data) {
    if (data.length < 4 ||
        data[0] != SettingsCommands.getDisplayPosition ||
        data[1] != SettingsCommands.responseSuccess) {
      return null;
    }
    return DisplayPosition(
      height: data[2].clamp(minHeight, maxHeight),
      depth: data[3].clamp(minDepth, maxDepth),
    );
  }
}

/// Whether the glasses notice they have been taken off.
abstract final class WearDetection {
  /// `27 <enable>` — both arms.
  static Uint8List buildSetCommand(bool enabled) => Uint8List.fromList([
        SettingsCommands.setWearDetection,
        enabled ? 0x01 : 0x00,
      ]);

  static Uint8List buildGetCommand() =>
      Uint8List.fromList([SettingsCommands.getWearDetection]);

  /// Response is `3A C9 <enabled>`.
  static bool? parseResponse(List<int> data) {
    if (data.length < 3 ||
        data[0] != SettingsCommands.getWearDetection ||
        data[1] != SettingsCommands.responseSuccess) {
      return null;
    }
    return data[2] == 0x01;
  }
}

/// Silent mode mutes the display entirely.
abstract final class SilentMode {
  static const int _on = 0x0C;
  static const int _off = 0x0A;

  /// `03 0C` to enable, `03 0A` to disable — both arms.
  static Uint8List buildSetCommand(bool enabled) => Uint8List.fromList([
        SettingsCommands.setSilentMode,
        enabled ? _on : _off,
      ]);

  static Uint8List buildGetCommand() =>
      Uint8List.fromList([SettingsCommands.getSilentMode]);

  /// Response is `2B 69 <0C|0A> ...`.
  static bool? parseResponse(List<int> data) {
    if (data.length < 3 || data[0] != SettingsCommands.getSilentMode) {
      return null;
    }
    return data[2] == _on;
  }
}

/// Firmware build string and uptime, for the device information screen.
abstract final class DeviceInfo {
  /// `23 74` — the reply is raw ASCII with no header.
  static Uint8List buildFirmwareCommand() =>
      Uint8List.fromList([SettingsCommands.deviceInfo, 0x74]);

  static Uint8List buildUptimeCommand() =>
      Uint8List.fromList([SettingsCommands.timeSinceBoot]);

  /// `23 72` restarts the glasses. There is no response.
  static Uint8List buildHardResetCommand() =>
      Uint8List.fromList([SettingsCommands.deviceInfo, 0x72]);

  /// Pulls the printable part out of the firmware reply, which starts with a
  /// few binary bytes before the "net build time: ..." text.
  static String? parseFirmware(List<int> data) {
    final text = String.fromCharCodes(
      data.where((b) => b >= 0x20 && b < 0x7F),
    ).trim();
    return text.isEmpty ? null : text;
  }

  /// Response is `37 <uint32 little endian seconds> ...`.
  static Duration? parseUptime(List<int> data) {
    if (data.length < 5 || data[0] != SettingsCommands.timeSinceBoot) {
      return null;
    }
    final seconds =
        data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
    return Duration(seconds: seconds);
  }
}

/// Wipes whatever is currently on the lens.
abstract final class ClearScreen {
  static Uint8List buildCommand() =>
      Uint8List.fromList([SettingsCommands.clearScreen]);
}


/// How the glasses lay out their dashboard.
///
/// The original code carried this as three opaque byte arrays. Decoded against
/// the protocol they are `06 07 00 <seq> 06 <mode> <pane>`: the dashboard
/// command, a total length of seven, a pad, a sequence number, the "set mode"
/// subcommand, then the layout and the pane that fills it.
enum DashboardMode {
  full(0x00, 'Full'),
  dual(0x01, 'Dual'),
  minimal(0x02, 'Minimal');

  const DashboardMode(this.id, this.label);

  final int id;
  final String label;

  /// Minimal has no room for a second pane, so the choice is hidden there.
  bool get hasSecondaryPane => this != DashboardMode.minimal;
}

/// What fills the second pane on the Full and Dual layouts.
enum DashboardPane {
  notes(0x00, 'Notes'),
  stock(0x01, 'Stock graph'),
  news(0x02, 'News'),
  calendar(0x03, 'Calendar'),
  navigation(0x04, 'Navigation'),
  empty(0x05, 'Empty');

  const DashboardPane(this.id, this.label);

  final int id;
  final String label;
}

/// Builds the dashboard layout command.
abstract final class DashboardLayoutCommand {
  /// Total packet length, counted by the protocol including the header.
  static const int _length = 0x07;

  static Uint8List build({
    required DashboardMode mode,
    required DashboardPane pane,
    required int sequence,
  }) {
    return Uint8List.fromList([
      SettingsCommands.dashboard,
      _length,
      0x00, // pad
      sequence & 0xFF,
      0x06, // subcommand: set dashboard mode
      mode.id,
      // Zero when the mode has no second pane, not the "empty" pane id.
      //
      // The official app's captured commands end in 0x00 for minimal, and
      // those bytes are the authority here — the protocol was read off the
      // wire, not from a specification. Sending 0x05 was a guess that
      // looked more expressive and matched nothing.
      mode.hasSecondaryPane ? pane.id : 0x00,
    ]);
  }
}

/// Some settings, height and depth among them, are only accepted while the
/// glasses are in debug mode. Turning it on is a single byte.
abstract final class DebugMode {
  static Uint8List buildSetCommand(bool enabled) => Uint8List.fromList([
        SettingsCommands.setDebugMode,
        enabled ? 0x01 : 0x00,
      ]);
}


/// The head-up angle is measured from a reference the wearer sets: the
/// position their head is in when looking straight ahead.
///
/// Without it, "display wakes at 30 degrees" means thirty degrees from
/// whatever the glasses last decided was level, which drifts with how they
/// sit on a face. Calibrating is what makes the angle setting mean anything.
///
/// The official app performs a fixed exchange, captured in the protocol
/// notes. Nothing here is inferred: it is that sequence, replayed.
abstract final class ZeroCalibration {
  /// Subcommand that opens calibration and puts the prompt on the lens.
  static const int _begin = 0x0C;

  /// Subcommand the glasses send once the wearer confirms on the touchpad.
  static const int acknowledged = 0x0D;

  /// Subcommand that closes it.
  static const int _finish = 0x05;

  /// `39 05 00 5f 01` — sent to both arms first.
  static Uint8List buildPrelude() => Uint8List.fromList(
        [SettingsCommands.calibrationPrelude, 0x05, 0x00, 0x5F, 0x01],
      );

  /// `50 06 00 00 01 01` — right arm only. Holds the dashboard still so it
  /// does not paint over the calibration prompt.
  static Uint8List buildDashboardLock() => Uint8List.fromList(
        [SettingsCommands.dashboardLock, 0x06, 0x00, 0x00, 0x01, 0x01],
      );

  /// `10 07 00 0c 02 01 00` — both arms. The lens then asks the wearer to
  /// look straight ahead and confirm.
  static Uint8List buildBegin() => Uint8List.fromList(
        [SettingsCommands.flow, 0x07, 0x00, _begin, 0x02, 0x01, 0x00],
      );

  /// `10 07 00 05 02 00 00` — both arms, once the wearer has confirmed.
  static Uint8List buildFinish() => Uint8List.fromList(
        [SettingsCommands.flow, 0x07, 0x00, _finish, 0x02, 0x00, 0x00],
      );

  /// True when a frame is the glasses reporting that the wearer confirmed.
  ///
  /// Shape is `10 06 00 0d 02 c9`: the flow command, the acknowledgement
  /// subcommand, and the generic success byte.
  static bool isAcknowledgement(List<int> data) {
    if (data.length < 6) return false;
    return data[0] == SettingsCommands.flow &&
        data[3] == acknowledged &&
        data[5] == SettingsCommands.responseSuccess;
  }

  /// True when a frame acknowledges one of the steps we sent.
  static bool isStepAccepted(List<int> data, int subcommand) {
    if (data.length < 6) return false;
    return data[0] == SettingsCommands.flow &&
        data[3] == subcommand &&
        data[5] == SettingsCommands.responseSuccess;
  }

  static const int beginSubcommand = _begin;
  static const int finishSubcommand = _finish;
}
