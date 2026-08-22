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

  Future<BrightnessSetting?> readBrightness() => _ask(
        BrightnessSetting.buildGetCommand(),
        SettingsCommands.getBrightness,
        BrightnessSetting.parseResponse,
      );

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

  Future<String?> readFirmware() => _ask(
        DeviceInfo.buildFirmwareCommand(),
        SettingsCommands.deviceInfo,
        DeviceInfo.parseFirmware,
      );

  Future<Duration?> readUptime() => _ask(
        DeviceInfo.buildUptimeCommand(),
        SettingsCommands.timeSinceBoot,
        DeviceInfo.parseUptime,
      );

  // ---------------------------------------------------------------- writing

  Future<void> setBrightness(BrightnessSetting setting) async {
    await _sendRight(setting.buildSetCommand());
    await _remember('glasses_brightness', setting.level);
    await _remember('glasses_brightness_auto', setting.auto);
  }

  Future<void> setHeadUpAngle(HeadUpAngle angle) async {
    await _sendRight(angle.buildSetCommand());
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

    try {
      await _sendRight(
        position.buildSetCommand(sequence: sequence, preview: true),
      );
      await Future.delayed(previewFor);
    } finally {
      await _sendRight(
        position.buildSetCommand(sequence: sequence, preview: false),
      );
    }

    await _remember('glasses_display_height', position.height);
    await _remember('glasses_display_depth', position.depth);
  }

  Future<void> setWearDetection(bool enabled) async {
    await _sendBoth(WearDetection.buildSetCommand(enabled));
    await _remember('glasses_wear_detection', enabled);
  }

  Future<void> setSilentMode(bool enabled) async {
    await _sendBoth(SilentMode.buildSetCommand(enabled));
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
    await _sendRight(command);

    final data = await reply;
    if (data == null) return null;

    try {
      return parse(data);
    } catch (e) {
      debugPrint('GlassesSettingsService: could not parse reply: $e');
      return null;
    }
  }

  /// Settings that live on one radio are read from and written to the right
  /// arm, per the protocol notes.
  Future<void> _sendRight(List<int> command) async {
    final right = _bluetooth.rightGlass;
    if (right == null) {
      debugPrint('GlassesSettingsService: right arm not connected');
      return;
    }
    await right.sendData(command);
  }

  Future<void> _sendBoth(List<int> command) async {
    await _bluetooth.sendCommandToGlasses(command);
  }

  Future<void> _remember(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }
}
