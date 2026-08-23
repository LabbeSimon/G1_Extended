import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/notification_history.dart';

/// Who, in this app, is actually holding the glasses.
///
/// The app runs a BluetoothManager in two isolates — the interface starts
/// one and the background service starts another — and each is a separate
/// object with its own connection, its own battery reading and its own
/// idea of what is going on. Whichever isolate the platform delivers a
/// notification to is not necessarily the one drawing the screen, which is
/// consistent with a battery that never appears, a temple tap that shows
/// nothing, and two lenses drifting apart.
///
/// "Consistent with" is not "proven", and this file exists to close that
/// gap rather than let a plausible story stand in for a measurement. Each
/// isolate can describe itself; the debug screen asks both and shows them
/// side by side, and the answer settles what to fix.
class IsolateReport {
  const IsolateReport._();

  /// A short name for the isolate this runs in.
  static String get name {
    final debugName = Isolate.current.debugName;
    if (debugName == null || debugName.isEmpty) return 'unnamed';
    return debugName;
  }

  /// What this isolate believes about the glasses.
  static Map<String, Object?> describe() {
    final bluetooth = BluetoothManager.singleton;
    final battery = bluetooth.batteryStatus;

    return {
      'isolate': name,
      'left': bluetooth.leftGlass == null
          ? 'absent'
          : (bluetooth.leftGlass!.isConnected == true ? 'connected' : 'idle'),
      'right': bluetooth.rightGlass == null
          ? 'absent'
          : (bluetooth.rightGlass!.isConnected == true ? 'connected' : 'idle'),
      'isConnected': bluetooth.isConnected == true,
      'batteryLeft': battery.leftBattery?.percentage,
      'batteryRight': battery.rightBattery?.percentage,
      'batteryUpdated': battery.lastUpdated.toIso8601String(),
      'caseBattery': bluetooth.caseBattery?.percentage,
      'receivingNotifications': bluetooth.isReceivingNotifications,
      'historyHeld': NotificationHistory.singleton.items.length,
      'displayOutOfStep': bluetooth.displayOutOfStep,
    };
  }

  /// Answers the interface's request for this isolate's description.
  ///
  /// Called from the background service's start-up; the reply comes back on
  /// a second channel because the messaging is one-way per name.
  static void serveFrom(ServiceInstance service) {
    service.on('describeIsolate').listen((_) {
      service.invoke('isolateDescription', describe());
    });
  }

  /// Asks the background service to describe itself. Null when it does not
  /// answer, which is itself an answer: it is not running.
  static Future<Map<String, dynamic>?> askBackground({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final service = FlutterBackgroundService();
    final completer = Completer<Map<String, dynamic>?>();

    late StreamSubscription<Map<String, dynamic>?> subscription;
    subscription = service.on('isolateDescription').listen((event) {
      if (!completer.isCompleted) completer.complete(event);
    });

    try {
      service.invoke('describeIsolate');
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('IsolateReport: background did not answer: $e');
      return null;
    } finally {
      await subscription.cancel();
    }
  }
}
