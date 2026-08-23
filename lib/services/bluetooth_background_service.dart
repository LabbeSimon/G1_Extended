import 'dart:async';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';
import 'package:g1_extended/utils/battery_optimization_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BluetoothBackgroundService {
  static const String _channelId = 'bluetooth_background_service';
  static const int _notificationId = 999;

  static Timer? _heartbeatTimer;
  static Timer? _connectionMonitorTimer;
  static BluetoothManager? _bluetoothManager;
  static BluetoothReciever? _bluetoothReceiver;
  static bool _isRunning = false;

  /// Initialize and start the background service
  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();

      // Create notification channel for Android
      try {
        final flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          _channelId,
          'G1 Extended',
          description: 'Maintains connection to your glasses in the background',
          importance: Importance
              .max, // Changed from high to max for better background processing
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      } catch (e) {
        // Handle notification initialization errors (e.g., in test environment)
        debugPrint(
            'BluetoothBackgroundService: Failed to initialize notifications: $e');
        if (kDebugMode) {
          // In debug/test mode, this is acceptable
          debugPrint(
              'BluetoothBackgroundService: Continuing without notifications in test environment');
        } else {
          rethrow;
        }
      }

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'G1 Extended',
          initialNotificationContent: 'Connected to glasses',
          foregroundServiceNotificationId: _notificationId,
          autoStartOnBoot: false,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
    } catch (e) {
      // Handle platform-specific errors (e.g., when running tests)
      debugPrint(
          'BluetoothBackgroundService: Platform not supported or in test environment: $e');
      if (kDebugMode) {
        // In debug/test mode, this is acceptable
        debugPrint(
            'BluetoothBackgroundService: Service initialization skipped in test environment');
        return;
      } else {
        rethrow;
      }
    }
  }

  /// Show or update the connection notification immediately
  static Future<void> showConnectionNotification({
    bool isConnected = true,
    bool leftConnected = false,
    bool rightConnected = false,
  }) async {
    try {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

      String status;
      if (isConnected) {
        status = 'Connected to glasses';
      } else if (leftConnected || rightConnected) {
        status =
            'Partially connected (${leftConnected ? 'L' : ''}${rightConnected ? 'R' : ''})';
      } else {
        status = 'Disconnected - trying to reconnect...';
      }

      await flutterLocalNotificationsPlugin.show(
        _notificationId,
        'G1 Extended',
        status,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'G1 Extended',
            icon: 'app_logo',
            ongoing: true,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.service,
            showWhen: true,
            usesChronometer: false,
            playSound: false,
            enableVibration: false,
            autoCancel: false,
            setAsGroupSummary: false,
          ),
        ),
      );
      debugPrint(
          'BluetoothBackgroundService: Connection notification shown - $status');
    } catch (e) {
      debugPrint(
          'BluetoothBackgroundService: Failed to show connection notification: $e');
    }
  }

  /// Start the background service
  static Future<void> start() async {
    try {
      // Check if already running to prevent multiple instances
      if (await isRunning()) {
        debugPrint(
            'BluetoothBackgroundService: Service already running, ignoring start request');
        return;
      }

      final service = FlutterBackgroundService();
      await service.startService();
    } catch (e) {
      // Handle platform-specific errors (e.g., when running tests)
      debugPrint('BluetoothBackgroundService: Failed to start service: $e');
      if (kDebugMode) {
        // In debug/test mode, this is acceptable
        debugPrint(
            'BluetoothBackgroundService: Service start skipped in test environment');
        return;
      } else {
        rethrow;
      }
    }
  }

  /// Stop the background service
  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke("stop");
      _heartbeatTimer?.cancel();
      _isRunning = false;
    } catch (e) {
      // Handle platform-specific errors (e.g., when running tests)
      debugPrint('BluetoothBackgroundService: Failed to stop service: $e');
      if (kDebugMode) {
        // In debug/test mode, this is acceptable
        debugPrint(
            'BluetoothBackgroundService: Service stop skipped in test environment');
        _heartbeatTimer?.cancel();
        _isRunning = false;
        return;
      } else {
        rethrow;
      }
    }
  }

  /// Check if the service is running
  static Future<bool> isRunning() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      // Handle platform-specific errors (e.g., when running tests)
      debugPrint(
          'BluetoothBackgroundService: Failed to check service status: $e');
      if (kDebugMode) {
        // In debug/test mode, return false as a safe default
        debugPrint(
            'BluetoothBackgroundService: Returning false for service status in test environment');
        return false;
      } else {
        rethrow;
      }
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    debugPrint('BluetoothBackgroundService: Starting background service');

    // Prevent multiple instances
    if (_isRunning) {
      debugPrint(
          'BluetoothBackgroundService: Service already running, ignoring start');
      return;
    }

    _isRunning = true;

    // Initialize Bluetooth Manager and Receiver with error handling
    try {
      _bluetoothManager = BluetoothManager.singleton;
      await _bluetoothManager!.initialize();

      // Initialize Bluetooth Receiver to handle voice commands
      _bluetoothReceiver = BluetoothReciever.singleton;

      // Try to reconnect to previously connected glasses
      await _bluetoothManager!.attemptReconnectFromStorage();

      // Set external heartbeat management to prevent duplicate heartbeats
      _bluetoothManager!.setExternalHeartbeatManaged(true);
    } catch (e) {
      debugPrint(
          'BluetoothBackgroundService: Failed to initialize or reconnect: $e');
      _isRunning = false;
      service.stopSelf();
      return;
    }

    // Start heartbeat timer - send every 28 seconds as per protocol
    _startHeartbeatTimer();

    // Start connection monitoring timer - check every 60 seconds
    _startConnectionMonitorTimer();

    // Listen for service stop
    service.on('stop').listen((event) {
      debugPrint('BluetoothBackgroundService: Received stop command');
      _stopService();
      service.stopSelf();
    });

    // Update notification every 60 seconds to show connection status
    Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!_isRunning) {
        timer.cancel();
        return;
      }

      try {
        await _updateNotification(service);
      } catch (e) {
        debugPrint(
            'BluetoothBackgroundService: Error updating notification: $e');
      }
    });

    debugPrint(
        'BluetoothBackgroundService: Background service started successfully');
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    debugPrint('BluetoothBackgroundService: iOS background mode');
    return true;
  }

  static void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();

    // Send heartbeat every 15 seconds (protocol disconnects after 32 seconds without heartbeat)
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isRunning || _bluetoothManager == null) {
        timer.cancel();
        return;
      }

      try {
        await _sendHeartbeat();
      } catch (e) {
        // Deliberately not reconnecting from here.
        //
        // A failing heartbeat means the link is already down, and the link
        // going down is what Glass listens for — its own reconnect loop is
        // running by the time this fires. Starting another from here meant
        // that while the glasses were away, this fired every fifteen seconds
        // and each failure kicked off a third attempt alongside the loop and
        // the monitor below.
        debugPrint('BluetoothBackgroundService: Heartbeat failed: $e');
      }
    });
  }

  static Future<void> _sendHeartbeat() async {
    try {
      if (_bluetoothManager?.leftGlass?.isConnected == true) {
        await _bluetoothManager!.leftGlass!.sendHeartbeat();
      }

      if (_bluetoothManager?.rightGlass?.isConnected == true) {
        await _bluetoothManager!.rightGlass!.sendHeartbeat();
      }

      debugPrint('BluetoothBackgroundService: Heartbeat sent');
    } catch (e) {
      debugPrint('BluetoothBackgroundService: Error sending heartbeat: $e');
    }
  }

  static Future<void> _attemptReconnect() async {
    debugPrint('BluetoothBackgroundService: Attempting to reconnect...');

    try {
      if (_bluetoothManager == null) {
        _bluetoothManager = BluetoothManager.singleton;
        await _bluetoothManager!.initialize();
      }

      await _bluetoothManager!.attemptReconnectFromStorage();

      // Re-enable external heartbeat management
      _bluetoothManager!.setExternalHeartbeatManaged(true);
    } catch (e) {
      debugPrint('BluetoothBackgroundService: Reconnection failed: $e');
    }
  }

  /// A safety net, not the mechanism.
  ///
  /// Reconnection belongs to Glass, which is told the moment the link drops.
  /// This exists only for the case that leaves no event behind — the whole
  /// stack having been torn down under us — so it runs slowly and stands
  /// aside whenever a reconnect is already in progress.
  ///
  /// It used to run every fifteen seconds and reconnect unconditionally, so
  /// with the glasses away it competed with the reconnect loop and with the
  /// heartbeat's own retry: three attempts on the radio, roughly six hundred
  /// wake-ups an hour between them, none aware of the others.
  static const Duration _monitorInterval = Duration(minutes: 2);

  static void _startConnectionMonitorTimer() {
    _connectionMonitorTimer?.cancel();

    _connectionMonitorTimer = Timer.periodic(_monitorInterval, (timer) async {
      if (!_isRunning || _bluetoothManager == null) {
        timer.cancel();
        return;
      }

      try {
        final manager = _bluetoothManager!;
        if (manager.isConnected || manager.isReconnecting) return;

        debugPrint(
            'BluetoothBackgroundService: down with no reconnect running, '
            'starting one');
        await _attemptReconnect();
      } catch (e) {
        debugPrint('BluetoothBackgroundService: Connection monitor error: $e');
      }
    });
  }

  static Future<void> _updateNotification(ServiceInstance service) async {
    try {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          final isConnected = _bluetoothManager?.isConnected ?? false;
          final leftConnected =
              _bluetoothManager?.leftGlass?.isConnected ?? false;
          final rightConnected =
              _bluetoothManager?.rightGlass?.isConnected ?? false;

          String status;
          if (isConnected) {
            status = 'Connected to glasses';
          } else if (leftConnected || rightConnected) {
            status =
                'Partially connected (${leftConnected ? 'L' : ''}${rightConnected ? 'R' : ''})';
          } else {
            status = 'Disconnected - trying to reconnect...';
          }

          final flutterLocalNotificationsPlugin =
              FlutterLocalNotificationsPlugin();
          await flutterLocalNotificationsPlugin.show(
            _notificationId,
            'G1 Extended',
            status,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                'G1 Extended',
                icon: 'app_logo',
                ongoing: true,
                importance: Importance
                    .max, // Changed from high to max for better persistence
                priority: Priority
                    .max, // Changed from high to max for better persistence
                category: AndroidNotificationCategory.service,
                showWhen: true,
                usesChronometer: false,
                playSound: false,
                enableVibration: false,
                // Add these for better background service persistence
                autoCancel: false,
                setAsGroupSummary: false,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(
          'BluetoothBackgroundService: Error in _updateNotification: $e');
    }
  }

  static void _stopService() {
    debugPrint('BluetoothBackgroundService: Stopping service');
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = null;

    // Re-enable internal heartbeat management
    if (_bluetoothManager != null) {
      _bluetoothManager!.setExternalHeartbeatManaged(false);
    }

    // Clean up Bluetooth receiver
    _bluetoothReceiver?.dispose();
    _bluetoothReceiver = null;
  }

  /// Request battery optimization exemption for better background performance
  static Future<void> requestBatteryOptimizationExemption() async {
    // This will help the app stay active in the background
    try {
      final isDisabled =
          await BatteryOptimizationHelper.isBatteryOptimizationDisabled();
      if (!isDisabled) {
        debugPrint(
            'BluetoothBackgroundService: Battery optimization is enabled, performance may be limited');
        debugPrint(
            'BluetoothBackgroundService: ${BatteryOptimizationHelper.getBatteryOptimizationExplanation()}');
      } else {
        debugPrint(
            'BluetoothBackgroundService: Battery optimization is disabled, good for background performance');
      }
    } catch (e) {
      debugPrint(
          'BluetoothBackgroundService: Error checking battery optimization: $e');
    }
  }
}
