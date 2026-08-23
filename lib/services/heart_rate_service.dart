import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/heart_rate.dart';

/// A heart rate sensor, live, next to the glasses.
///
/// The phone already holds one BLE link per temple; this adds a third to
/// whatever broadcasts the standard Heart Rate service — a chest strap, or
/// a watch with broadcast turned on. Standard by design: no vendor app, no
/// account, no cloud, and any sensor speaking the profile works, including
/// ones that do not exist yet.
class HeartRateService {
  HeartRateService._internal();
  static final HeartRateService singleton = HeartRateService._internal();
  factory HeartRateService() => singleton;

  /// The assigned numbers: Heart Rate service, and its measurement.
  static final Guid serviceUuid = Guid('180D');
  static final Guid measurementUuid = Guid('2A37');

  static const String _deviceKey = 'heart_rate_device';
  static const String _nameKey = 'heart_rate_device_name';

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _measurements;
  StreamSubscription<BluetoothConnectionState>? _connection;
  bool _running = false;

  final StreamController<HeartRateMeasurement> _controller =
      StreamController<HeartRateMeasurement>.broadcast();

  /// Live measurements while a sensor is connected.
  Stream<HeartRateMeasurement> get stream => _controller.stream;

  HeartRateMeasurement? _last;
  DateTime? _lastAt;

  /// The latest reading, provided it is fresh enough to trust. A cardio
  /// number is only ever now: thirty seconds old it is a lie with a
  /// confident face.
  HeartRateMeasurement? get current {
    final at = _lastAt;
    if (at == null) return null;
    if (DateTime.now().difference(at) > const Duration(seconds: 15)) {
      return null;
    }
    return _last;
  }

  bool get isRunning => _running;

  Future<String?> rememberedName() async =>
      (await SharedPreferences.getInstance()).getString(_nameKey);

  Future<bool> get hasRememberedDevice async =>
      (await SharedPreferences.getInstance()).getString(_deviceKey) != null;

  /// Scans for anything advertising the Heart Rate service.
  ///
  /// A plain scan filtered on the service uuid: sensors not advertising it
  /// do not appear, which is the honest behaviour — a watch with broadcast
  /// off is invisible, and no amount of listing it would make it send data.
  Stream<ScanResult> scan() {
    FlutterBluePlus.startScan(
      withServices: [serviceUuid],
      timeout: const Duration(seconds: 15),
    );
    return FlutterBluePlus.scanResults.expand((results) => results);
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Adopts a sensor: remembered, connected, streaming.
  Future<void> adopt(BluetoothDevice device, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, device.remoteId.str);
    await prefs.setString(_nameKey, name);
    await _connect(device);
  }

  /// Forgets the sensor and drops the link.
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceKey);
    await prefs.remove(_nameKey);
    await stop();
  }

  /// Connects to the remembered sensor, if there is one.
  Future<bool> start() async {
    if (_running) return true;

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_deviceKey);
    if (id == null) return false;

    await _connect(BluetoothDevice.fromId(id));
    return _running;
  }

  Future<void> stop() async {
    _running = false;
    await _measurements?.cancel();
    _measurements = null;
    await _connection?.cancel();
    _connection = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _last = null;
    _lastAt = null;
  }

  Future<void> _connect(BluetoothDevice device) async {
    await stop();
    _device = device;
    _running = true;

    // The sensor's own reconnection: straps drop and return constantly as
    // clothing moves. Glass has its own loop for the glasses; this one is
    // deliberately simpler — the platform's autoConnect does the waiting.
    _connection = device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        await _subscribe(device);
      }
    });

    try {
      await device.connect(
        autoConnect: true,
        mtu: null,
        timeout: const Duration(seconds: 20),
      );
    } catch (e) {
      debugPrint('HeartRateService: connect failed: $e');
    }
  }

  Future<void> _subscribe(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid != serviceUuid) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid != measurementUuid) continue;

          await characteristic.setNotifyValue(true);
          await _measurements?.cancel();
          _measurements = characteristic.lastValueStream.listen((data) {
            final measurement = HeartRateMeasurement.parse(data);
            if (measurement == null) return;
            _last = measurement;
            _lastAt = DateTime.now();
            if (!_controller.isClosed) _controller.add(measurement);
          });
          debugPrint('HeartRateService: streaming from ${device.remoteId}');
          return;
        }
      }
      debugPrint('HeartRateService: no measurement characteristic found');
    } catch (e) {
      debugPrint('HeartRateService: subscribe failed: $e');
    }
  }
}
