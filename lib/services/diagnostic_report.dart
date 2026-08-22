import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/services/battery_frame_log.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';

/// Builds a diagnostic report as a JSON file the user owns.
///
/// This is the app's answer to telemetry. Nothing is collected in the
/// background and nothing is transmitted: the report is written only when
/// asked for, its contents are listed on screen before it leaves, and where
/// it goes afterwards is the user's decision. Someone debugging their own
/// glasses can read it themselves; someone reporting a problem can attach it.
class DiagnosticReport {
  DiagnosticReport._internal();
  static final DiagnosticReport singleton = DiagnosticReport._internal();
  factory DiagnosticReport() => singleton;

  static const String _redactKey = 'diagnostics_redact';

  /// Whether identifying details are left out of the report.
  ///
  /// On by default. The one genuinely identifying thing here is the BLE name
  /// of each temple, which carries the pair's serial number: a report shared
  /// in public would tie a person to a specific pair of glasses. The operating
  /// system build string is close behind, being narrow enough to help
  /// fingerprint a device. Neither is needed to decode a protocol frame, so
  /// the default is to omit them and let anyone who does need them opt in.
  Future<bool> isRedacted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_redactKey) ?? true;
  }

  Future<void> setRedacted(bool redacted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_redactKey, redacted);
  }

  /// Everything the report will contain, as a map, so a screen can show the
  /// user exactly what they are about to share.
  Future<Map<String, dynamic>> build() async {
    final redacted = await isRedacted();
    final info = await PackageInfo.fromPlatform();
    final bluetooth = BluetoothManager.singleton;
    final log = BatteryFrameLog.singleton;

    return {
      'report': {
        'generatedAt': DateTime.now().toIso8601String(),
        'schema': 1,
        'redacted': redacted,
      },
      'app': {
        'version': info.version,
        'build': info.buildNumber,
        if (!redacted) 'package': info.packageName,
      },
      'platform': {
        'os': Platform.operatingSystem,
        // Everything below narrows the report to one device. Useful when you
        // are debugging your own phone, and nobody else's business.
        if (!redacted) ...await _deviceDetails(),
      },
      'glasses': {
        'connected': bluetooth.isConnected,
        'left': _describe(bluetooth.leftGlass, redacted: redacted),
        'right': _describe(bluetooth.rightGlass, redacted: redacted),
        'battery': {
          'left': bluetooth.batteryStatus.leftBattery?.percentage,
          'right': bluetooth.batteryStatus.rightBattery?.percentage,
          'case': bluetooth.caseBattery?.percentage,
          'caseSource': bluetooth.caseBattery?.source.name,
          'lastUpdated':
              bluetooth.batteryStatus.lastUpdated.toIso8601String(),
        },
      },
      'batteryFrames': {
        'recording': log.enabled,
        'capturedStates': log.capturedStates(),
        'varyingBytePositions': log.varyingPositions(),
        'byState': log.comparisonTable(),
        'frames': [
          for (final frame in log.frames)
            {
              'at': frame.at.toIso8601String(),
              'side': frame.side == GlassSide.left ? 'L' : 'R',
              'state': frame.note,
              'hex': frame.hex,
              'bytes': frame.bytes,
            },
        ],
      },
    };
  }

  /// Model, Android build and screen geometry. Any one of them narrows a
  /// report to a handful of devices; together they identify one.
  Future<Map<String, dynamic>> _deviceDetails() async {
    final details = <String, dynamic>{
      'osVersion': Platform.operatingSystemVersion,
    };

    try {
      if (Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        details.addAll({
          'manufacturer': android.manufacturer,
          'model': android.model,
          'device': android.device,
          'sdkInt': android.version.sdkInt,
          'release': android.version.release,
        });
      }
    } catch (e) {
      debugPrint('DiagnosticReport: could not read device info: $e');
    }

    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      details['screen'] = {
        'width': size.width.round(),
        'height': size.height.round(),
        'devicePixelRatio': view.devicePixelRatio,
      };
    } catch (e) {
      debugPrint('DiagnosticReport: could not read screen metrics: $e');
    }

    return details;
  }

  /// The BLE name carries the pair's serial number, so it is the first thing
  /// to go when the report is redacted.
  Map<String, dynamic>? _describe(Glass? glass, {required bool redacted}) {
    if (glass == null) return null;
    return {
      if (!redacted) 'name': glass.name,
      'connected': glass.isConnected == true,
    };
  }

  /// Writes the report and returns the file, ready to be shared.
  Future<File> write() async {
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${directory.path}/g1-extended-diagnostics-$stamp.json');

    final json = const JsonEncoder.withIndent('  ').convert(await build());
    await file.writeAsString(json);

    debugPrint('DiagnosticReport: wrote ${file.path}');
    return file;
  }
}
