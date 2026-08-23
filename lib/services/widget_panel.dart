import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/speedometer_service.dart';

/// Keeps the home screen widget telling the truth.
///
/// The widget's provider draws whatever was last saved for it and computes
/// nothing itself, so this is the single place that decides what it says.
/// Both isolates — the interface and the background service — push through
/// here; whichever one owns the Bluetooth link at the time is the one whose
/// numbers land.
/// What the widget's one button does.
enum WidgetButtonRole {
  /// Speed toggle when connected, reconnect when not — the default.
  adaptive('adaptive'),

  /// Only ever offers reconnect, and only when disconnected.
  reconnectOnly('reconnect'),

  /// No button at all; the whole tile just opens the app.
  none('none');

  const WidgetButtonRole(this.wire);

  /// The value written for the Kotlin provider to read. A rename here must
  /// be made in GlassesWidgetProvider.kt as well — the two sides share only
  /// these strings.
  final String wire;

  static WidgetButtonRole fromWire(String? value) => values.firstWhere(
        (role) => role.wire == value,
        orElse: () => adaptive,
      );
}

/// The widget's appearance choices.
class WidgetOptions {
  const WidgetOptions({
    this.showCase = true,
    this.alwaysBothSides = false,
    this.button = WidgetButtonRole.adaptive,
  });

  /// Whether the case battery appears when known.
  final bool showCase;

  /// Show L and R always, instead of only when they drift apart.
  final bool alwaysBothSides;

  final WidgetButtonRole button;
}

class WidgetPanel {
  const WidgetPanel._();

  static const String _provider = 'GlassesWidgetProvider';

  // The option keys the Kotlin provider reads. Its defaults must match the
  // ones in WidgetOptions, or a fresh install's widget would contradict the
  // settings screen until the first save.
  static const String _optCaseKey = 'opt_case';
  static const String _optBothKey = 'opt_both';
  static const String _optButtonKey = 'opt_button';

  /// Reads the stored choices, defaults where nothing was ever saved.
  static Future<WidgetOptions> readOptions() async {
    return WidgetOptions(
      showCase: await HomeWidget.getWidgetData<bool>(_optCaseKey) ?? true,
      alwaysBothSides:
          await HomeWidget.getWidgetData<bool>(_optBothKey) ?? false,
      button: WidgetButtonRole.fromWire(
        await HomeWidget.getWidgetData<String>(_optButtonKey),
      ),
    );
  }

  /// Stores the choices and redraws the widget with them at once.
  static Future<void> saveOptions(WidgetOptions options) async {
    await HomeWidget.saveWidgetData<bool>(_optCaseKey, options.showCase);
    await HomeWidget.saveWidgetData<bool>(_optBothKey, options.alwaysBothSides);
    await HomeWidget.saveWidgetData<String>(
        _optButtonKey, options.button.wire);
    await HomeWidget.updateWidget(androidName: _provider);
  }

  static Timer? _pending;
  static String? _lastWritten;

  /// Collapses bursts. Battery packets arrive in volleys around a
  /// connection, and rewriting the widget for each one would spend more
  /// power redrawing than the information is worth.
  static void schedule() {
    _pending ??= Timer(const Duration(seconds: 2), () {
      _pending = null;
      unawaited(update());
    });
  }

  /// Writes the current state out, if it differs from what the widget
  /// already shows.
  static Future<void> update() async {
    try {
      final bluetooth = BluetoothManager.singleton;
      final battery = bluetooth.batteryStatus;
      final connected = bluetooth.isConnected == true;
      final speedOn = await SpeedometerService.singleton.isEnabled();

      final left = battery.leftBattery?.percentage ?? -1;
      final right = battery.rightBattery?.percentage ?? -1;
      final casePct = bluetooth.caseBattery?.percentage ?? -1;

      // The stamp is when the data last changed, which is exactly what the
      // fingerprint must ignore: including it would make every write look
      // new, and excluding stale data from the redraw is the whole point.
      final fingerprint = '$connected|$left|$right|$casePct|$speedOn';
      if (fingerprint == _lastWritten) return;
      _lastWritten = fingerprint;

      final now = DateTime.now();
      final stamp = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      await HomeWidget.saveWidgetData<bool>('connected', connected);
      await HomeWidget.saveWidgetData<int>('left', left);
      await HomeWidget.saveWidgetData<int>('right', right);
      await HomeWidget.saveWidgetData<int>('case_pct', casePct);
      await HomeWidget.saveWidgetData<bool>('speed_on', speedOn);
      await HomeWidget.saveWidgetData<String>('stamp', stamp);
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (e) {
      // A widget that fails to update is stale, not broken. Never let it
      // take anything else down with it.
      debugPrint('WidgetPanel: could not update: $e');
    }
  }
}

/// Runs when a widget button is tapped, on its own short-lived engine.
///
/// This isolate holds no Bluetooth link and no running services — it can
/// write preferences and pass word along, nothing more. So it does exactly
/// that: record what the user asked, redraw the widget so the tap visibly
/// landed, and hand the request to the long-lived isolates through the
/// background service, where a connected BluetoothManager can act on it.
@pragma('vm:entry-point')
Future<void> widgetInteractionCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri == null) return;

  switch (uri.host) {
    case 'speed':
      final prefs = await SharedPreferences.getInstance();
      // Fresh from disk: this isolate's cache was born empty, but reload
      // makes that explicit rather than incidental.
      await prefs.reload();
      final enabled = !(prefs.getBool('speedometer_enabled') ?? false);
      await prefs.setBool('speedometer_enabled', enabled);

      // Redraw first. The state change must be visible on the tap, not on
      // whenever the service gets around to confirming it.
      await HomeWidget.saveWidgetData<bool>('speed_on', enabled);
      await HomeWidget.updateWidget(androidName: 'GlassesWidgetProvider');

      _tellTheApp({'action': 'speed'});

    case 'reconnect':
      _tellTheApp({'action': 'reconnect'});
  }
}

void _tellTheApp(Map<String, dynamic> command) {
  try {
    FlutterBackgroundService().invoke('widgetCommand', command);
  } catch (e) {
    // The service is not running. The preference is already written, so the
    // request is not lost — it takes effect the next time the app starts.
    debugPrint('WidgetPanel: no service to tell: $e');
  }
}
