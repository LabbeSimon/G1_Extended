import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

typedef OnNotification = void Function(ServiceNotificationEvent);

class AndroidNotificationsListener {
  final OnNotification onData;

  AndroidNotificationsListener({required this.onData});

  Future<void> startListening({bool requestIfDenied = false}) async {
    final bool hasPermission =
        await NotificationListenerService.isPermissionGranted();

    if (!hasPermission) {
      if (!requestIfDenied) {
        return;
      }

      await NotificationListenerService.requestPermission();

      final bool grantedNow =
          await NotificationListenerService.isPermissionGranted();
      if (!grantedNow) {
        return;
      }
    }

    NotificationListenerService.notificationsStream.listen((event) {
      if (event.hasRemoved == null || event.hasRemoved == false) {
        onData(event);
      }
    });
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
