import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Everything the report will contain, as a map, so a screen can show the
  /// user exactly what they are about to share.
  Future<Map<String, dynamic>> build() async {
    final info = await PackageInfo.fromPlatform();
    final bluetooth = BluetoothManager.singleton;
    final log = BatteryFrameLog.singleton;

    return {
      'report': {
        'generatedAt': DateTime.now().toIso8601String(),
        'schema': 1,
      },
      'app': {
        'version': info.version,
        'build': info.buildNumber,
        'package': info.packageName,
      },
      'platform': {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      },
      'glasses': {
        'connected': bluetooth.isConnected,
        'left': _describe(bluetooth.leftGlass),
        'right': _describe(bluetooth.rightGlass),
        'battery': {
          'left': bluetooth.batteryStatus.leftBattery?.percentage,
          'right': bluetooth.batteryStatus.rightBattery?.percentage,
          'lastUpdated':
              bluetooth.batteryStatus.lastUpdated.toIso8601String(),
        },
      },
      'batteryFrames': {
        'recording': log.enabled,
        'varyingBytePositions': log.varyingPositions(),
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

  Map<String, dynamic>? _describe(Glass? glass) {
    if (glass == null) return null;
    return {
      'name': glass.name,
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
