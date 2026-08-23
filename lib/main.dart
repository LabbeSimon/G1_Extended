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
    // The interface's copy: screens and relays, no periodic machinery.
    // The background service owns the glasses and runs the timers.
    await _step('bluetooth',
        () => BluetoothManager.singleton.initialize(ownsGlasses: false));
    // The service owns the glasses and broadcasts what it sees; this copy
    // feeds those broadcasts into the streams every screen already uses.
    FlutterBackgroundService().on('glassesState').listen((state) {
      if (state != null) BluetoothManager.singleton.adoptRemoteState(state);
    });
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

/// Hive, for whichever isolate is asking.
///
/// It used to run only from main — that is, only in the interface isolate.
/// The background service runs in its own isolate with its own Hive
/// instance, uninitialised, so everything it tried to read or write there
/// failed: the notification blocklist read as empty, and anything the
/// glasses' touchpad triggered could not reach storage at all.
Future<void> initHiveForThisIsolate() => _initHive();

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
