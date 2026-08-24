import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';

/// Reads and writes the settings held by the glasses themselves.
///
/// The glasses are the source of truth: every getter here asks the hardware
/// rather than trusting a local copy, because the wearer can change some of
/// these from the temple buttons. Values are cached only so a settings screen
/// has something to draw before the first reply arrives.
class GlassesSettingsService {
  GlassesSettingsService._internal();
  static final GlassesSettingsService singleton =
      GlassesSettingsService._internal();
  factory GlassesSettingsService() => singleton;

  BluetoothManager get _bluetooth => BluetoothManager.singleton;
  BluetoothReciever get _receiver => BluetoothReciever.singleton;

  int _displaySequence = 0;

  // ---------------------------------------------------------------- reading

  /// Reads the brightness the glasses are actually using, and caches it.
  ///
  /// The cache used to be written only when the app *set* a value, which made
  /// it a record of what this app had done rather than of what the hardware
  /// was doing. Anyone who had turned automatic brightness on from the
  /// official app, or reinstalled this one, got the default — off — until
  /// they opened the brightness screen, which asks the glasses directly.
  Future<BrightnessSetting?> readBrightness() async {
    final setting = await _ask(
      BrightnessSetting.buildGetCommand(),
      SettingsCommands.getBrightness,
      BrightnessSetting.parseResponse,
    );
    if (setting != null) {
      await _remember('glasses_brightness', setting.level);
      await _remember('glasses_brightness_auto', setting.auto);
    }
    return setting;
  }

  Future<HeadUpAngle?> readHeadUpAngle() => _ask(
        HeadUpAngle.buildGetCommand(),
        SettingsCommands.getHeadUpAngle,
        HeadUpAngle.parseResponse,
      );

  Future<DisplayPosition?> readDisplayPosition() => _ask(
        DisplayPosition.buildGetCommand(),
        SettingsCommands.getDisplayPosition,
        DisplayPosition.parseResponse,
      );

  Future<bool?> readWearDetection() => _ask(
        WearDetection.buildGetCommand(),
        SettingsCommands.getWearDetection,
        WearDetection.parseResponse,
      );

  Future<bool?> readSilentMode() => _ask(
        SilentMode.buildGetCommand(),
        SettingsCommands.getSilentMode,
        SilentMode.parseResponse,
      );

  // No readFirmware() here on purpose. [_ask] matches a reply to its request
  // by the command byte the glasses echo back, but the firmware reply carries
  // no header at all: it starts with 0x02 and is raw ASCII from there. Wiring
  // it to the generic path would silently time out on every call. The command
  // builder and parser in DeviceInfo are kept and tested, ready for whoever
  // adds a payload-matching path for it.

  Future<Duration?> readUptime() => _ask(
        DeviceInfo.buildUptimeCommand(),
        SettingsCommands.timeSinceBoot,
        DeviceInfo.parseUptime,
      );

  // ---------------------------------------------------------------- writing

  Future<void> setBrightness(BrightnessSetting setting) async {
    await _sendBoth(setting.buildSetCommand());
    await _remember('glasses_brightness', setting.level);
    await _remember('glasses_brightness_auto', setting.auto);
  }

  Future<void> setHeadUpAngle(HeadUpAngle angle) async {
    await _sendBoth(angle.buildSetCommand());
    await _remember('glasses_headup_angle', angle.degrees);
  }

  /// Applies a display position using the two-step preview the glasses
  /// require: show it, give the wearer [previewFor] to judge it, then commit.
  ///
  /// Skipping the commit leaves the display permanently on, so it runs in a
  /// `finally` even if the preview send fails.
  Future<void> setDisplayPosition(
    DisplayPosition position, {
    Duration previewFor = const Duration(seconds: 3),
  }) async {
    final sequence = _displaySequence = (_displaySequence + 1) & 0xFF;

    await setDebugMode(true);
    try {
      await _sendBoth(
        position.buildSetCommand(sequence: sequence, preview: true),
      );
      await Future.delayed(previewFor);
    } finally {
      await _sendBoth(
        position.buildSetCommand(sequence: sequence, preview: false),
      );
      await setDebugMode(false);
    }

    await _remember('glasses_display_height', position.height);
    await _remember('glasses_display_depth', position.depth);
  }

  /// Sets the dashboard layout and what fills its second pane.
  Future<void> setDashboardLayout({
    required DashboardMode mode,
    required DashboardPane pane,
  }) async {
    _displaySequence = (_displaySequence + 1) & 0xFF;
    await _sendBoth(DashboardLayoutCommand.build(
      mode: mode,
      pane: pane,
      sequence: _displaySequence,
    ));
    await _remember('dashboard_mode', mode.index);
    await _remember('dashboard_pane', pane.index);
  }

  /// Height and depth are only accepted while the glasses are in debug mode,
  /// so it is turned on for the length of the change and off again after.
  Future<void> setDebugMode(bool enabled) async {
    await _sendBoth(DebugMode.buildSetCommand(enabled));
  }

  Future<void> setWearDetection(bool enabled) async {
    await _sendBoth(WearDetection.buildSetCommand(enabled));
    await _remember('glasses_wear_detection', enabled);
  }

  Future<void> setSilentMode(bool enabled) async {
    await _sendBoth(SilentMode.buildSetCommand(enabled));
  }

  /// Runs the head-up zero calibration.
  ///
  /// The wearer is asked, on the lens, to look straight ahead and confirm on
  /// the touchpad. This waits for that confirmation, then closes the flow.
  ///
  /// Returns true when the wearer confirmed, false on timeout or refusal.
  /// The closing command is sent either way: leaving the glasses in
  /// calibration mode would keep the dashboard locked.
  Future<bool> calibrateZeroAngle({
    Duration waitForWearer = const Duration(seconds: 45),
  }) async {
    if (!_bluetooth.isConnected) return false;

    await _sendBoth(ZeroCalibration.buildPrelude());
    await Future.delayed(const Duration(milliseconds: 120));

    await _sendBoth(ZeroCalibration.buildDashboardLock());
    await Future.delayed(const Duration(milliseconds: 120));

    // Registered before sending, or a quick wearer could confirm before
    // anyone is listening.
    //
    // The 0x10 family carries more than the wearer's confirmation: the
    // glasses answer buildBegin itself with a "step accepted" 0x10 first,
    // subcommand 0x0C, before the wearer has done anything. Matching on the
    // command byte alone let that immediate accept complete the wait, which
    // is why calibration used to report "not confirmed" the instant the
    // prompt appeared — it never actually waited for the touchpad.
    final confirmation = _receiver.awaitReply(
      SettingsCommands.flow,
      timeout: waitForWearer,
      accept: ZeroCalibration.isAcknowledgement,
    );

    await _sendBoth(ZeroCalibration.buildBegin());

    try {
      final reply = await confirmation;
      return reply != null && ZeroCalibration.isAcknowledgement(reply);
    } finally {
      await _sendBoth(ZeroCalibration.buildFinish());
    }
  }

  /// Puts every glasses-side setting back where it started.
  Future<void> restoreDefaults() async {
    await setBrightness(const BrightnessSetting(level: 20, auto: false));
    await setHeadUpAngle(const HeadUpAngle(30));
    await setWearDetection(true);
    await setSilentMode(false);
    await setDashboardLayout(
      mode: DashboardMode.dual,
      pane: DashboardPane.notes,
    );
    await setDisplayPosition(const DisplayPosition(height: 4, depth: 5));
  }

  Future<void> clearScreen() async {
    await _sendBoth(ClearScreen.buildCommand());
  }

  /// Restarts the glasses. They drop the BLE link and reconnect on their own.
  Future<void> restartGlasses() async {
    await _sendBoth(DeviceInfo.buildHardResetCommand());
  }

  // ----------------------------------------------------------------- cached

  /// Last known values, for drawing a settings screen before the glasses reply.
  Future<Map<String, Object>> cachedValues() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'brightness': prefs.getInt('glasses_brightness') ?? 20,
      'brightnessAuto': prefs.getBool('glasses_brightness_auto') ?? false,
      'headUpAngle': prefs.getInt('glasses_headup_angle') ?? 30,
      'displayHeight': prefs.getInt('glasses_display_height') ?? 4,
      'displayDepth': prefs.getInt('glasses_display_depth') ?? 5,
      'wearDetection': prefs.getBool('glasses_wear_detection') ?? true,
      'dashboardMode': prefs.getInt('dashboard_mode') ?? DashboardMode.dual.index,
      'dashboardPane': prefs.getInt('dashboard_pane') ?? DashboardPane.notes.index,
    };
  }

  // ---------------------------------------------------------------- plumbing

  /// Sends [command] and waits for the glasses to answer with [replyCommand].
  Future<T?> _ask<T>(
    Uint8List command,
    int replyCommand,
    T? Function(List<int>) parse,
  ) async {
    if (!_bluetooth.isConnected) return null;

    final reply = _receiver.awaitReply(replyCommand);
    await _sendBoth(command);

    final data = await reply;
    if (data == null) return null;

    try {
      return parse(data);
    } catch (e) {
      debugPrint('GlassesSettingsService: could not parse reply: $e');
      return null;
    }
  }

  /// Every settings command, every reply-carrying request included.
  ///
  /// These used to go to the right arm alone, on the strength of the
  /// protocol notes — the same notes that turned out to route notifications
  /// and the allowlist to the wrong arm too. even_glasses, a reference this
  /// app was never forked from and so shares no bug with, sends every
  /// settings command to both temples unconditionally; nothing here has
  /// been confirmed as genuinely one-arm. A reply reaching both radios
  /// completes the request on the first arrival and the second is logged
  /// and dropped, harmlessly.
  Future<void> _sendBoth(List<int> command) async {
    await _bluetooth.sendCommandToGlasses(command);
  }

  Future<void> _remember(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }
}
