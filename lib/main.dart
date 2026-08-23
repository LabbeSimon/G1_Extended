import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:g1_extended/models/dashboard/calendar.dart';
import 'package:g1_extended/models/dashboard/checklist.dart';
import 'package:g1_extended/models/dashboard/daily.dart';
import 'package:g1_extended/models/dashboard/stop.dart';
import 'package:g1_extended/screens/home_screen.dart';
import 'package:g1_extended/services/bluetooth_background_service.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/crash_reporter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:g1_extended/services/widget_panel.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/services/speedometer_service.dart';
import 'package:g1_extended/services/stops_manager.dart';
import 'package:g1_extended/services/voice_pipeline.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/utils/third_party_licences.dart';
import 'package:g1_extended/utils/ui_perfs.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String APP_NAME = 'G1 Extended';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // First, before anything that could fail. Installing the handlers after
    // the work has started means the failures worth catching most — the ones
    // during start-up — are the ones that go unrecorded.
    await CrashReporter.singleton.install();
    await CrashReporter.singleton.begin();

    registerThirdPartyLicences();

    await _step('notifications', () async {
      await flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('app_logo'),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final actionId = response.actionId;
          if (actionId != null && actionId.startsWith('delete_')) {
            _handleDeleteAction(actionId);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
    });

    await _step('storage', _initHive);
    await _step('preferences', UiPerfs.singleton.load);
    await _step('background service', BluetoothBackgroundService.initialize);
    await _step(
      'battery exemption',
      BluetoothBackgroundService.requestBatteryOptimizationExemption,
    );
    await _step('bluetooth', BluetoothManager.singleton.initialize);
    // Brings forward anything the four-slot version wrote, before anything
    // reads the box.
    await _step('notes', NotesLibrary.singleton.migrate);
    await _step('speedometer', SpeedometerService.singleton.start);
    await _step('home widget', () async {
      // The callback below runs widget taps on a background engine; the
      // listener mirrors, in this isolate, whatever the background service
      // just did about one.
      await HomeWidget.registerInteractivityCallback(widgetInteractionCallback);
      FlutterBackgroundService().on('widgetCommandApplied').listen((event) {
        unawaited(SpeedometerService.singleton.syncWithPreference());
        if (event?['action'] == 'reconnect') {
          BluetoothManager.singleton.hurryReconnect();
        }
      });
      WidgetPanel.schedule();
    });
    await _step('voice pipeline', VoicePipeline.singleton.start);
    await _step('legacy service', _startLegacyBackgroundService);

    runApp(const G1ExtendedApp());
  } catch (e, stackTrace) {
    debugPrint('Fatal error during app initialization: $e\n$stackTrace');
    runApp(_StartupFailure(error: e));
  }
}

/// Runs one start-up step without letting it take the whole app down.
///
/// Every step here is optional in the sense that the app is still usable
/// without it — a missing permission or an unavailable radio should degrade
/// the experience, not prevent launch.
Future<void> _step(String name, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    debugPrint('Startup step "$name" failed: $e');
  }
}

Future<void> _startLegacyBackgroundService() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    debugPrint('Background service already running');
    return;
  }

  const channel = MethodChannel('fr.simonlabbe.g1extended/background_service');
  final handle = PluginUtilities.getCallbackHandle(backgroundMain);
  await channel.invokeMethod('startService', handle?.toRawHandle());
}

@pragma('vm:entry-point')
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
}

class G1ExtendedApp extends StatelessWidget {
  const G1ExtendedApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: APP_NAME,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.dark,
      home: const AppRetainWidget(child: HomeScreen()),
    );
  }
}

/// On Android, backing out of the home screen sends the app to the background
/// instead of killing it, so the glasses stay connected.
class AppRetainWidget extends StatelessWidget {
  const AppRetainWidget({super.key, required this.child});

  final Widget child;

  static const _channel = MethodChannel('fr.simonlabbe.g1extended/app_retain');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !Platform.isAndroid) return;

        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }

        try {
          await _channel.invokeMethod('sendToBackground');
        } catch (e) {
          debugPrint('Could not send app to background: $e');
        }
      },
      child: child,
    );
  }
}

/// Shown only when initialisation threw before the app could start.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: APP_NAME,
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 56),
                const SizedBox(height: 20),
                const Text('The app could not start'),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: main, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initHive() async {
  try {
    // Initialize Hive
    await Hive.initFlutter();

    // Register adapters
    try {
      Hive.registerAdapter(DailyItemAdapter());
      Hive.registerAdapter(StopItemAdapter());
      Hive.registerAdapter(DashboardCalendarAdapter());
      Hive.registerAdapter(ChecklistEntryAdapter());
      Hive.registerAdapter(ChecklistAdapter());
    } catch (e) {
      // Adapters might already be registered
      debugPrint('Hive adapters already registered or error registering: $e');
    }

    // Open boxes with error handling
    try {
      if (!Hive.isBoxOpen('dailyBox')) {
        await Hive.openBox<DailyItem>('dailyBox');
      }
    } catch (e) {
      debugPrint('Failed to open dailyBox: $e');
    }

    try {
      if (!Hive.isBoxOpen('stopBox')) {
        await Hive.openLazyBox<StopItem>('stopBox');
      }
    } catch (e) {
      debugPrint('Failed to open stopBox: $e');
    }

    try {
      if (!Hive.isBoxOpen('calendarBox')) {
        await Hive.openBox<DashboardCalendar>('calendarBox');
      }
    } catch (e) {
      debugPrint('Failed to open calendarBox: $e');
    }

    try {
      if (!Hive.isBoxOpen('checklistBox')) {
        await Hive.openBox<Checklist>('checklistBox');
      }
    } catch (e) {
      debugPrint('Failed to open checklistBox: $e');
    }

    try {
      if (!Hive.isBoxOpen('appPrefs')) {
        await Hive.openBox('appPrefs');
      }
    } catch (e) {
      debugPrint('Failed to open appPrefs: $e');
    }

    try {
      if (!Hive.isBoxOpen('customCards')) {
        await Hive.openBox('customCards');
      }
    } catch (e) {
      debugPrint('Failed to open customCards: $e');
    }
  } catch (e) {
    debugPrint('Critical error initializing Hive: $e');
    rethrow;
  }
}

// this will be used as notification channel id
const notificationChannelId = 'my_foreground';

// this will be used for notification id, So you can update your custom notification with this id.
const notificationId = 888;

Future<void> initializeService() async {
  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'G1 Extended', // title
    description: 'Keeps the glasses connected in the background.',
    importance: Importance.low, // importance must be at low or higher level
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: false,

      notificationChannelId:
          notificationChannelId, // this must match with notification channel you created above.
      initialNotificationTitle: APP_NAME,
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: notificationId,

      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  try {
    // Only available for flutter 3.0.0 and later
    //DartPluginRegistrant.ensureInitialized();

    // Initialize Hive safely
    try {
      await Hive.initFlutter();

      // Register adapters if not already registered
      try {
        Hive.registerAdapter(DailyItemAdapter());
        Hive.registerAdapter(StopItemAdapter());
        Hive.registerAdapter(DashboardCalendarAdapter());
        Hive.registerAdapter(ChecklistEntryAdapter());
        Hive.registerAdapter(ChecklistAdapter());
      } catch (e) {
        debugPrint('Adapters already registered: $e');
      }

      // Open boxes safely
      try {
        if (!Hive.isBoxOpen('dailyBox')) {
          await Hive.openBox<DailyItem>('dailyBox');
        }
      } catch (e) {
        debugPrint('Failed to open dailyBox in background service: $e');
      }

      try {
        if (!Hive.isBoxOpen('stopBox')) {
          await Hive.openLazyBox<StopItem>('stopBox');
        }
      } catch (e) {
        debugPrint('Failed to open stopBox in background service: $e');
      }

      try {
        if (!Hive.isBoxOpen('appPrefs')) {
          await Hive.openBox('appPrefs');
        }
      } catch (e) {
        debugPrint('Failed to open appPrefs in background service: $e');
      }
    } catch (e) {
      debugPrint('Failed to initialize Hive in background service: $e');
    }

    // Initialize BluetoothManager safely
    try {
      final bt = BluetoothManager.singleton;
      await bt.initialize();
      if (!bt.isConnected) {
        bt.attemptReconnectFromStorage();
      }
    } catch (e) {
      debugPrint('Failed to initialize Bluetooth in background service: $e');
    }

    // Foreground service periodic task
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // Check if service is still running to prevent memory leaks
        if (!(await FlutterBackgroundService().isRunning())) {
          timer.cancel();
          return;
        }

        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            await flutterLocalNotificationsPlugin.show(
              notificationId,
              APP_NAME,
              'Active ${DateTime.now().toString().substring(11, 19)}',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  notificationChannelId,
                  '$APP_NAME Background Service',
                  icon: 'app_logo',
                  ongoing: true,
                  autoCancel: false,
                  playSound: false,
                  enableVibration: false,
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error in background service periodic task: $e');
      }
    });
  } catch (e) {
    debugPrint('Critical error in background service onStart: $e');
  }
}

void startBackgroundService() {
  final service = FlutterBackgroundService();
  service.startService();
}

void stopBackgroundService() {
  final service = FlutterBackgroundService();
  service.invoke("stop");
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('notificationTapBackground: $notificationResponse');
  if (notificationResponse.actionId == null) {
    return;
  }

  if (notificationResponse.actionId!.startsWith("delete_")) {
    _handleDeleteAction(notificationResponse.actionId!);
  }

  // handle action
}

void _handleDeleteAction(String actionId) async {
  if (actionId.startsWith("delete_")) {
    final id = actionId.split("_")[1];
    try {
      // Ensure box is open
      if (!Hive.isBoxOpen('stopBox')) {
        await Hive.openLazyBox<StopItem>('stopBox');
      }

      final box = Hive.lazyBox<StopItem>('stopBox');
      debugPrint('Deleting item with id: $id');

      for (var i = 0; i < box.length; i++) {
        try {
          final item = await box.getAt(i);
          if (item?.uuid == id) {
            debugPrint('Deleting item at index: $i');
            await box.deleteAt(i);
            await box.flush();
            break;
          }
        } catch (e) {
          debugPrint('Error processing item at index $i: $e');
        }
      }

      try {
        StopsManager().reload();
      } catch (e) {
        debugPrint('Error reloading StopsManager: $e');
      }
    } catch (e) {
      debugPrint('Error in _handleDeleteAction: $e');
    }
  }
}
