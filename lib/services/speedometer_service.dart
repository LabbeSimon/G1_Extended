import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/navigation_service.dart';

enum SpeedUnit {
  kmh('km/h', 3.6),
  mph('mph', 2.23694);

  const SpeedUnit(this.label, this.fromMetresPerSecond);

  final String label;
  final double fromMetresPerSecond;
}

/// Shows the current speed on the glasses, read from the phone's GPS.
///
/// The reading never leaves the device: the position is turned into a number
/// of km/h on the phone and only that number is drawn on the lens.
///
/// The glasses are not a car dashboard. Their text area is repainted as a
/// whole and each repaint costs battery, so the speed is only redrawn when it
/// has actually changed by a meaningful amount — not on every GPS fix.
class SpeedometerService {
  SpeedometerService._internal();
  static final SpeedometerService singleton = SpeedometerService._internal();
  factory SpeedometerService() => singleton;

  static const String _enabledKey = 'speedometer_enabled';
  static const String _unitKey = 'speedometer_unit';

  /// Below this, GPS speed is mostly noise and a parked phone would show a
  /// jittering number.
  static const double _stationaryThresholdKmh = 2;

  /// Redraw only past this much change, so a steady cruise stays still.
  static const double _minimumChange = 2;

  static const Duration _minimumInterval = Duration(seconds: 2);

  StreamSubscription<Position>? _positions;
  SpeedUnit _unit = SpeedUnit.kmh;
  double? _lastShown;
  DateTime? _lastSent;
  String? _label;

  /// The current reading, for the phone's own UI and for the navigation line.
  String? get label => _label;

  bool get isRunning => _positions != null;

  SpeedUnit get unit => _unit;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<SpeedUnit> readUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_unitKey) ?? SpeedUnit.kmh.index;
    return SpeedUnit.values[index];
  }

  Future<void> setUnit(SpeedUnit unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unitKey, unit.index);
    _unit = unit;
    _lastShown = null;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  /// Starts following the GPS, if the user asked for it and granted location.
  Future<void> start() async {
    if (_positions != null) return;
    if (!await isEnabled()) return;

    _unit = await readUnit();

    if (!await _hasPermission()) {
      debugPrint('SpeedometerService: location not granted');
      return;
    }

    _positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Metres, not seconds: a stationary phone produces no fixes at all,
        // which is exactly the behaviour wanted here.
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (Object e) {
      debugPrint('SpeedometerService: position stream failed: $e');
    });
  }

  Future<void> stop() async {
    await _positions?.cancel();
    _positions = null;
    _lastShown = null;
    _lastSent = null;
    _label = null;
  }

  Future<void> _onPosition(Position position) async {
    final speed = format(position.speed, _unit);
    _label = speed;

    if (speed == null) return;

    final value = position.speed * _unit.fromMetresPerSecond;
    if (!_worthRedrawing(value)) return;

    _lastShown = value;
    _lastSent = DateTime.now();

    // Directions come first; when navigating, the speed rides along on the
    // instruction line instead of fighting it for the display.
    if (NavigationService.singleton.isNavigating) return;
    if (!BluetoothManager.singleton.isConnected) return;

    try {
      await BluetoothManager.singleton.sendPriorityText(speed);
    } catch (e) {
      debugPrint('SpeedometerService: could not display speed: $e');
    }
  }

  bool _worthRedrawing(double value) {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minimumInterval) {
      return false;
    }
    if (_lastShown == null) return true;
    return (value - _lastShown!).abs() >= _minimumChange;
  }

  /// Formats a speed in metres per second, or null when there is nothing
  /// meaningful to show.
  @visibleForTesting
  static String? format(double metresPerSecond, SpeedUnit unit) {
    if (metresPerSecond.isNaN || metresPerSecond < 0) return null;

    final converted = metresPerSecond * unit.fromMetresPerSecond;
    if (converted < _stationaryThresholdKmh) return '0 ${unit.label}';

    return '${converted.round()} ${unit.label}';
  }

  Future<bool> _hasPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
