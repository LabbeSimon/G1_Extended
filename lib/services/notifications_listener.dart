import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

typedef OnNotification = void Function(ServiceNotificationEvent);

class AndroidNotificationsListener {
  final OnNotification onData;

  AndroidNotificationsListener({required this.onData});

  StreamSubscription<ServiceNotificationEvent>? _subscription;

  /// True once the app is actually receiving notifications.
  bool get isListening => _subscription != null;

  /// Subscribes to the notification stream, if access has been granted.
  ///
  /// Calling this again is safe and is in fact the point: access is granted
  /// on a system settings page, long after the app started, and nothing
  /// tells the app when it happens. Without a second attempt the user grants
  /// access, comes back, and nothing works until the app is restarted —
  /// which looks exactly like the permission not having been granted at all.
  Future<bool> startListening({bool requestIfDenied = false}) async {
    if (_subscription != null) return true;

    var granted = await NotificationListenerService.isPermissionGranted();

    if (!granted && requestIfDenied) {
      await NotificationListenerService.requestPermission();
      granted = await NotificationListenerService.isPermissionGranted();
    }

    if (!granted) {
      debugPrint('AndroidNotificationsListener: access not granted');
      return false;
    }

    _subscription = NotificationListenerService.notificationsStream
        .listen((event) {
      if (event.hasRemoved == null || event.hasRemoved == false) {
        onData(event);
      }
    });

    debugPrint('AndroidNotificationsListener: listening');
    return true;
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Whether the user has granted notification access in system settings.
  ///
  /// This is not a runtime permission: Android puts it behind a dedicated
  /// settings page, so it has to be asked about rather than requested.
  Future<bool> isGranted() async {
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint('AndroidNotificationsListener: could not check access: $e');
      return false;
    }
  }

  Future<void> requestPermission() async {
    await NotificationListenerService.requestPermission();
  }
}
