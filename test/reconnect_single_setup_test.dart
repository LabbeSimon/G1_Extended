import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/glass.dart';

/// Only one connection-setup sequence may run against a temple at a time.
///
/// The connection-state stream emits the current state the moment it is
/// subscribed — "disconnected", since connect() subscribes before connecting —
/// which schedules the auto-reconnect loop in parallel with the initial
/// connection. When the initial connect took longer than the loop's first
/// two-second delay, two setup sequences ran against the same device: the
/// losing one's cleanup (device.disconnect, uartTx = null) was the winning
/// one's PlatformException(discoverServices, device is disconnected).
class FakeBluetoothDevice extends BluetoothDevice {
  FakeBluetoothDevice()
      : super(remoteId: const DeviceIdentifier('00:11:22:33:44:55'));

  final _stateController =
      StreamController<BluetoothConnectionState>.broadcast(sync: true);
  var _state = BluetoothConnectionState.disconnected;

  /// How long connect() blocks — longer than the reconnect loop's first
  /// delay, so a spurious parallel setup would overlap with the initial one.
  Duration connectDelay = const Duration(seconds: 5);

  int connectCalls = 0;
  int discoverCalls = 0;
  int _inFlightConnects = 0;
  int maxConcurrentConnects = 0;

  void _setState(BluetoothConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  @override
  bool get isConnected => _state == BluetoothConnectionState.connected;

  @override
  Stream<BluetoothConnectionState> get connectionState async* {
    // Like flutter_blue_plus: the current state is emitted on subscription.
    yield _state;
    yield* _stateController.stream;
  }

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    connectCalls++;
    _inFlightConnects++;
    if (_inFlightConnects > maxConcurrentConnects) {
      maxConcurrentConnects = _inFlightConnects;
    }
    await Future.delayed(connectDelay);
    _inFlightConnects--;
    _setState(BluetoothConnectionState.connected);
  }

  @override
  Future<void> disconnect({
    int timeout = 35,
    bool queue = true,
    int androidDelay = 2000,
  }) async {
    _setState(BluetoothConnectionState.disconnected);
  }

  @override
  Future<List<BluetoothService>> discoverServices(
      {bool subscribeToServicesChanged = true, int timeout = 15}) async {
    discoverCalls++;
    if (!isConnected) {
      throw Exception('discoverServices: device is disconnected');
    }
    return [];
  }

  @override
  Future<int> requestMtu(int desiredMtu,
      {double predelay = 0.35, int timeout = 15}) async {
    return desiredMtu;
  }

  @override
  Future<void> requestConnectionPriority(
      {required ConnectionPriority connectionPriorityRequest}) async {}
}

void main() {
  test('a slow initial connect does not spawn a second parallel setup', () {
    fakeAsync((async) {
      final device = FakeBluetoothDevice();
      final glass = Glass(name: 'L', device: device, side: GlassSide.left);
      // The background service normally owns the heartbeat; keeping it
      // external here stops the periodic timer from running under fakeAsync.
      glass.setExternalHeartbeatManaged(true);

      var connected = false;
      glass.connect().then((_) => connected = true);

      // Enough time for the initial connect (5s), the state listener's
      // spurious reconnect loop (first attempt at 2s, mid-connect), and a
      // few more of its rounds if it were still running.
      async.elapse(const Duration(seconds: 30));

      expect(connected, isTrue);
      expect(device.maxConcurrentConnects, 1,
          reason: 'two setup sequences ran against the same device');
      expect(device.discoverCalls, 1,
          reason: 'services were discovered by more than one setup sequence');
      expect(glass.isReconnecting, isFalse);

      glass.disconnect();
      async.flushMicrotasks();
    });
  });

  test('a real disconnection still reconnects exactly once', () {
    fakeAsync((async) {
      final device = FakeBluetoothDevice()
        ..connectDelay = const Duration(milliseconds: 100);
      final glass = Glass(name: 'R', device: device, side: GlassSide.right);
      glass.setExternalHeartbeatManaged(true);

      glass.connect();
      async.elapse(const Duration(seconds: 10));
      expect(device.isConnected, isTrue);
      final callsAfterFirstSetup = device.connectCalls;

      // The temple drops: interference, out of range for a moment.
      device.disconnect();
      async.elapse(const Duration(seconds: 10));

      expect(device.isConnected, isTrue,
          reason: 'the auto-reconnect loop never brought the temple back');
      expect(device.connectCalls, callsAfterFirstSetup + 1,
          reason: 'the drop triggered more than one reconnection');
      expect(glass.isReconnecting, isFalse);

      glass.disconnect();
      async.flushMicrotasks();
    });
  });
}
