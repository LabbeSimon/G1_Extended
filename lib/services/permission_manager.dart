import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Logical groups of permissions that map to user-facing features.
/// Only what the manifest actually declares. Offering to grant a permission
/// the app does not request produces a dialog that cannot succeed.
enum AppPermission {
  bluetooth,
  location,
  notifications,

  /// Reading the notifications other apps post, which is the whole point of
  /// the glasses and is not a runtime permission at all.
  notificationAccess,

  calendar,
  microphone,
  batteryOptimization,
}

/// Metadata describing a logical permission group.
class PermissionDefinition {
  const PermissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.permissions,
    this.requiredForCoreFlow = false,
    this.androidOnly = false,
    this.iosOnly = false,
  });

  final AppPermission id;
  final String title;
  final String description;
  final List<Permission> permissions;
  final bool requiredForCoreFlow;
  final bool androidOnly;
  final bool iosOnly;
}

/// Snapshot of the current status for a permission group.
class PermissionSummary {
  PermissionSummary({
    required this.definition,
    required this.statuses,
    this.delegatedGranted,
  });

  final PermissionDefinition definition;
  final Map<Permission, PermissionStatus> statuses;

  /// Set for groups a plugin handles itself, where permission_handler has no
  /// suitable constant. Null for the ordinary case.
  final bool? delegatedGranted;

  bool get allGranted {
    final delegated = delegatedGranted;
    if (delegated != null) return delegated;

    // An empty status map used to read as "granted", which is right for a
    // platform that does not need the permission and wrong for one that
    // simply failed to report.
    if (statuses.isEmpty) {
      return true;
    }
    return statuses.values.every((status) => status.isGranted);
  }

  bool get anyPermanentlyDenied =>
      delegatedGranted == null &&
      statuses.values.any((status) => status.isPermanentlyDenied);

  bool get anyDenied => delegatedGranted != null
      ? !delegatedGranted!
      : statuses.values.any((s) => s.isDenied || s.isRestricted);
}

class PermissionManager {
  static final List<PermissionDefinition> _definitions = [
    const PermissionDefinition(
      id: AppPermission.bluetooth,
      title: 'Glasses & Nearby Devices',
      description:
          'Needed to scan, pair, and stay connected with your Even Realities G1 glasses.',
      permissions: [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ],
      requiredForCoreFlow: true,
      androidOnly: true,
    ),
    const PermissionDefinition(
      id: AppPermission.location,
      title: 'Location',
      description:
          'Android requires it to scan for Bluetooth devices. Also used for '
          'local weather and, if you enable it, the speed readout.',
      permissions: [
        Permission.location,
      ],
      requiredForCoreFlow: false,
    ),
    const PermissionDefinition(
      id: AppPermission.notifications,
      title: 'Show notifications',
      description:
          'Lets this app post its own alerts — the ongoing one that keeps the '
          'glasses connected in the background. It does not let it read '
          'anything.',
      permissions: [
        Permission.notification,
      ],
      requiredForCoreFlow: false,
    ),
    // Two entries that sound alike and are unrelated. The one above is
    // POST_NOTIFICATIONS: permission to show alerts. The one below is
    // notification listener access: permission to read the alerts other apps
    // post, which is what gets put on the glasses.
    //
    // Only the first was ever offered, so the app asked to *send*
    // notifications and never to *read* them. Everything downstream was
    // correct — the manifest declares the listener service, the stream is
    // subscribed, the blocklist lets everything through — and no notification
    // could ever arrive, with nothing anywhere saying why.
    //
    // It is also granted per package name, so access given to an earlier
    // build under a different application id does not carry over.
    const PermissionDefinition(
      id: AppPermission.notificationAccess,
      title: 'Read notifications',
      description:
          'Required to put your notifications on the glasses. Android keeps '
          'this behind its own settings page rather than a dialog, so this '
          'opens that page.',
      permissions: [],
      requiredForCoreFlow: true,
      androidOnly: true,
    ),
    const PermissionDefinition(
      id: AppPermission.calendar,
      title: 'Calendar',
      description:
          'Used when you connect calendars so events and reminders appear across devices.',
      // permission_handler has no read-only calendar permission on Android:
      // both of its calendar constants map to READ_CALENDAR *and*
      // WRITE_CALENDAR. This app only reads, so it declares only
      // READ_CALENDAR — and asking for either constant then requests a
      // permission the manifest does not declare, which Android refuses
      // without ever showing a dialog. device_calendar asks for the right
      // one, so the calendar group defers to it.
      permissions: [],
      requiredForCoreFlow: false,
    ),
    const PermissionDefinition(
      id: AppPermission.microphone,
      title: 'Microphone',
      description:
          'Enable when you want hands-free voice notes or voice-controlled features.',
      permissions: [
        Permission.microphone,
      ],
      requiredForCoreFlow: false,
    ),
    const PermissionDefinition(
      id: AppPermission.batteryOptimization,
      title: 'Battery Optimization',
      description:
          'Needed only if you want the background Bluetooth service to stay active without interruption.',
      permissions: [
        Permission.ignoreBatteryOptimizations,
      ],
      requiredForCoreFlow: false,
      androidOnly: true,
    ),
  ];

  static List<PermissionDefinition> get availableDefinitions {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const [];
    }

    return _definitions.where((definition) {
      if (definition.androidOnly && !Platform.isAndroid) {
        return false;
      }
      if (definition.iosOnly && !Platform.isIOS) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  static PermissionDefinition definitionOf(AppPermission id) {
    return _definitions.firstWhere((definition) => definition.id == id);
  }

  /// Groups with no permission_handler permission behind them, handled by
  /// the plugin that actually needs the access.
  static bool _isDelegated(AppPermission id) =>
      id == AppPermission.calendar || id == AppPermission.notificationAccess;

  static Future<bool> _delegatedGranted(AppPermission id) =>
      id == AppPermission.calendar
          ? _calendarGranted()
          : _notificationAccessGranted();

  static Future<bool> _requestDelegated(AppPermission id) =>
      id == AppPermission.calendar
          ? _requestCalendar()
          : _requestNotificationAccess();

  static Future<bool> _notificationAccessGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint('PermissionManager: could not read notification access: $e');
      return false;
    }
  }

  /// Opens the system page and reports what the user did there.
  ///
  /// Unlike a runtime permission this cannot be granted from a dialog, so the
  /// call returns as soon as the page opens and the answer has to be read
  /// back afterwards rather than taken from the return value.
  static Future<bool> _requestNotificationAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      await NotificationListenerService.requestPermission();
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint('PermissionManager: could not open notification access: $e');
      return false;
    }
  }

  static Future<bool> _calendarGranted() async {
    try {
      final result = await DeviceCalendarPlugin().hasPermissions();
      return result.data == true;
    } catch (e) {
      debugPrint('PermissionManager: could not read calendar access: $e');
      return false;
    }
  }

  static Future<bool> _requestCalendar() async {
    try {
      final result = await DeviceCalendarPlugin().requestPermissions();
      return result.data == true;
    } catch (e) {
      debugPrint('PermissionManager: could not request calendar access: $e');
      return false;
    }
  }

  static Future<PermissionSummary> getSummary(AppPermission id) async {
    final definition = definitionOf(id);
    final Map<Permission, PermissionStatus> statuses = {};

    if (_isDelegated(id)) {
      return PermissionSummary(
        definition: definition,
        statuses: {},
        delegatedGranted: await _delegatedGranted(id),
      );
    }

    final permissions = await _effectivePermissions(definition);

    if (!Platform.isAndroid && !Platform.isIOS) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    if (definition.androidOnly && !Platform.isAndroid) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    if (definition.iosOnly && !Platform.isIOS) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    for (final permission in permissions) {
      try {
        final status = await permission.status;
        statuses[permission] = status;
      } catch (error) {
        debugPrint(
          'PermissionManager: Failed to fetch status for ${permission.toString()}: $error',
        );
      }
    }

    return PermissionSummary(definition: definition, statuses: statuses);
  }

  static Future<PermissionSummary> requestPermissions(AppPermission id) async {
    if (_isDelegated(id)) {
      final granted = await _requestDelegated(id);
      return PermissionSummary(
        definition: definitionOf(id),
        statuses: {},
        delegatedGranted: granted,
      );
    }

    final definition = definitionOf(id);
    final Map<Permission, PermissionStatus> statuses = {};

    if (!Platform.isAndroid && !Platform.isIOS) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    if (definition.androidOnly && !Platform.isAndroid) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    if (definition.iosOnly && !Platform.isIOS) {
      return PermissionSummary(definition: definition, statuses: {});
    }

    final permissions = await _effectivePermissions(definition);

    for (final permission in permissions) {
      try {
        final currentStatus = await permission.status;
        if (currentStatus.isGranted) {
          statuses[permission] = currentStatus;
          continue;
        }

        final requestedStatus = await permission.request();
        statuses[permission] = requestedStatus;
      } catch (error) {
        debugPrint(
          'PermissionManager: Request failed for ${permission.toString()}: $error',
        );
      }
    }

    return PermissionSummary(definition: definition, statuses: statuses);
  }

  static Future<bool> ensureGranted(AppPermission id) async {
    if (_isDelegated(id)) {
      return await _delegatedGranted(id) || await _requestDelegated(id);
    }

    final summary = await getSummary(id);
    if (summary.allGranted) {
      return true;
    }

    final requested = await requestPermissions(id);
    return requested.allGranted;
  }

  static Future<List<Permission>> _effectivePermissions(
    PermissionDefinition definition,
  ) async {

    return definition.permissions;
  }

  /// The human-readable name of a permission group.
  static String titleFor(AppPermission id) {
    return _definitions
        .firstWhere((definition) => definition.id == id)
        .title;
  }

  static Future<bool> isGroupGranted(AppPermission id) async {
    if (_isDelegated(id)) return _calendarGranted();

    final summary = await getSummary(id);
    return summary.allGranted;
  }

  static Future<bool> openSettings() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        return false;
      }
      return await openAppSettings();
    } catch (error) {
      debugPrint('PermissionManager: Error opening settings: $error');
      return false;
    }
  }
}
