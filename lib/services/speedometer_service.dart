import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
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
  static const String _decimalsKey = 'speedometer_decimals';
  static const String _commaKey = 'speedometer_decimal_comma';
  static const String _clockKey = 'speedometer_show_clock';

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

  bool _decimals = false;
  bool _comma = false;
  bool _clock = false;

  Future<bool> showsDecimals() async =>
      (await SharedPreferences.getInstance()).getBool(_decimalsKey) ?? false;

  Future<bool> usesDecimalComma() async =>
      (await SharedPreferences.getInstance()).getBool(_commaKey) ??
      // Defaults to the separator of the phone's own locale rather than to a
      // point: writing 27.4 to someone whose every other number reads 27,4
      // is a small thing that reads as an untranslated app.
      Intl.getCurrentLocale().startsWith('fr');

  Future<bool> showsClock() async =>
      (await SharedPreferences.getInstance()).getBool(_clockKey) ?? false;

  Future<void> setDecimals(bool value) async {
    _decimals = value;
    await (await SharedPreferences.getInstance()).setBool(_decimalsKey, value);
  }

  Future<void> setDecimalComma(bool value) async {
    _comma = value;
    await (await SharedPreferences.getInstance()).setBool(_commaKey, value);
  }

  Future<void> setShowClock(bool value) async {
    _clock = value;
    await (await SharedPreferences.getInstance()).setBool(_clockKey, value);
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
    _decimals = await showsDecimals();
    _comma = await usesDecimalComma();
    _clock = await showsClock();

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
    ).listen(
      _onPosition,
      // Both of these used to be missing, or to only log.
      //
      // The stream ends on its own more often than it looks: location being
      // switched off and on, the platform suspending updates, a provider
      // changing underneath. When it did, the subscription field stayed
      // non-null while nothing was listening — and start() returns
      // immediately when that field is set, so the speed never came back for
      // the rest of the ride. Which is what "it cuts out sometimes" is.
      onError: (Object e) {
        debugPrint('SpeedometerService: position stream failed: $e');
        unawaited(_restart());
      },
      onDone: () {
        debugPrint('SpeedometerService: position stream ended');
        unawaited(_restart());
      },
    );
  }

  Timer? _restartTimer;

  /// Brings the stream back after it has ended.
  ///
  /// Delayed and debounced: whatever ended it — location switched off, a
  /// provider changing — is usually still true a moment later, and retrying
  /// in a tight loop would drain the battery faster than the GPS does.
  Future<void> _restart() async {
    if (_restartTimer?.isActive ?? false) return;

    await _positions?.cancel();
    _positions = null;

    _restartTimer = Timer(const Duration(seconds: 5), () async {
      if (_positions != null) return;
      if (!await isEnabled()) return;
      debugPrint('SpeedometerService: restarting the position stream');
      await start();
    });
  }

  Future<void> stop() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    await _positions?.cancel();
    _positions = null;
    _lastShown = null;
    _lastSent = null;
    _label = null;
  }

  Future<void> _onPosition(Position position) async {
    final speed = format(
      position.speed,
      _unit,
      decimals: _decimals,
      decimalComma: _comma,
    );
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
      await BluetoothManager.singleton.sendPriorityText(
        _clock ? withClock(speed, DateTime.now()) : speed,
      );
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
  /// The speed as it should appear on the lens.
  ///
  /// [decimals] adds a tenth, which is worth having on a bicycle where whole
  /// numbers flicker between two values at a steady pace. [decimalComma]
  /// writes it the way most of Europe does; the glasses' font has the
  /// character, so this is a choice rather than a limitation.
  static String? format(
    double metresPerSecond,
    SpeedUnit unit, {
    bool decimals = false,
    bool decimalComma = false,
  }) {
    if (metresPerSecond.isNaN || metresPerSecond < 0) return null;

    final converted = metresPerSecond * unit.fromMetresPerSecond;
    if (converted < _stationaryThresholdKmh) {
      final zero = decimals ? '0.0' : '0';
      return '${_punctuate(zero, decimalComma)} ${unit.label}';
    }

    final text =
        decimals ? converted.toStringAsFixed(1) : '${converted.round()}';
    return '${_punctuate(text, decimalComma)} ${unit.label}';
  }

  static String _punctuate(String value, bool comma) =>
      comma ? value.replaceAll('.', ',') : value;

  /// The speed with the time beside it.
  ///
  /// Optional because the lens is 640 by 200 and every character spent on
  /// something the wearer could get by tilting their head is a character not
  /// spent on the thing they are reading.
  static String withClock(String speed, DateTime now) {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$speed   $hh:$mm';
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
