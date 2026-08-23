import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/battery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'case_battery.dart';
import '../../services/battery_frame_log.dart';
import '../../services/bluetooth_manager.dart';
import '../../services/bluetooth_reciever.dart';
import '../../utils/constants.dart';

enum GlassSide { left, right }

// Define type for side button press callback
typedef SideButtonCallback = void Function();
// Define type for battery response callback
typedef BatteryResponseCallback = void Function(G1BatteryInfo batteryInfo);

class Glass {
  final String name;
  final GlassSide side;

  final BluetoothDevice device;

  BluetoothCharacteristic? uartTx;
  BluetoothCharacteristic? uartRx;

  StreamSubscription<List<int>>? notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? connectionStateSubscription;
  Timer? heartbeatTimer;
  int heartbeatSeq = 0;
  int _connectRetries = 0;
  static const int maxConnectRetries = 3;
  bool _externalHeartbeatManaged = false;
  bool _isReconnecting = false;

  // Callback function for when side button is pressed
  SideButtonCallback? onSideButtonPress;

  // Callback function for battery responses
  BatteryResponseCallback? onBatteryResponse;
  VoidCallback? onConnectionStateChanged;

  get isConnected => device.isConnected;

  BluetoothReciever reciever = BluetoothReciever.singleton;

  Glass({required this.name, required this.device, required this.side}) {
    // The side button is free for a caller to bind. Nothing is wired by
    // default: dictation is driven by the touchpad in BluetoothReciever.
  }

  Future<void> connect() async {
    try {
      // Cancel any existing subscriptions first
      await disconnect();

      // Set up connection state monitoring first
      connectionStateSubscription = device.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        debugPrint('[$side Glass] Connection state: $state');
        onConnectionStateChanged?.call();
        if (state == BluetoothConnectionState.disconnected && !_isReconnecting) {
          _scheduleReconnect();
        }
      });

      // Initial connection attempt
      await _connectWithRetry();
      _connectRetries = 0; // Reset counter after successful connection
      _isReconnecting = false;
    } catch (e) {
      debugPrint('[$side Glass] Connection error: $e');
      await disconnect();
      rethrow;
    }
  }

  Future<void> _connectWithRetry() async {
    try {
      if (!device.isConnected) {
        // Retry the connection up to maxConnectRetries times
        bool connected = false;
        int attempts = 0;
        while (!connected && attempts < maxConnectRetries) {
          try {
            attempts++;
            debugPrint(
              '[$side Glass] Trying to connect (attempt $attempts/$maxConnectRetries)',
            );
            await device.connect(timeout: const Duration(seconds: 15));
            connected = true;
          } catch (e) {
            debugPrint(
              '[$side Glass] Connection attempt $attempts failed: $e',
            );
            if (attempts < maxConnectRetries) {
              await Future.delayed(const Duration(seconds: 1));
            } else {
              throw Exception(
                'Failed to connect after $maxConnectRetries attempts',
              );
            }
          }
        }
      }

      // Once connected, proceed with service discovery and setup
      debugPrint('[$side Glass] Connected, discovering services...');
      await discoverServices();
      debugPrint('[$side Glass] Services discovered, setting up MTU...');
      await device.requestMtu(251);
      debugPrint('[$side Glass] Setting connection priority...');
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      startHeartbeat();
      debugPrint(
        '[$side Glass] Setup complete - connection established successfully',
      );
      onConnectionStateChanged?.call();
    } catch (e) {
      debugPrint('[$side Glass] Connection process failed: $e');
      rethrow; // Let the caller handle this error
    }
  }

  Future<void> discoverServices() async {
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString().toUpperCase() ==
          BluetoothConstants.UART_SERVICE_UUID) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.uuid.toString().toUpperCase() ==
              BluetoothConstants.UART_TX_CHAR_UUID) {
            if (c.properties.write) {
              uartTx = c;
              debugPrint('[$side Glass] UART TX Characteristic is writable.');
            } else {
              debugPrint(
                '[$side Glass] UART TX Characteristic is not writable.',
              );
            }
          } else if (c.uuid.toString().toUpperCase() ==
              BluetoothConstants.UART_RX_CHAR_UUID) {
            uartRx = c;
          }
        }
      }
    }
    if (uartRx != null) {
      await uartRx!.setNotifyValue(true);

      // Cancel before subscribing again.
      //
      // Service discovery runs on every connection, reconnections included,
      // and this assignment used to replace the field while leaving the
      // previous subscription alive and listening. After three reconnections
      // every incoming packet was handled three times: three notifications
      // pushed to the glasses, one touchpad press read as three.
      await notificationSubscription?.cancel();
      notificationSubscription = uartRx!.lastValueStream.listen(
        handleNotification,
      );
      debugPrint('[$side Glass] UART RX set to notify.');
    } else {
      debugPrint('[$side Glass] UART RX Characteristic not found.');
    }

    if (uartTx != null) {
      debugPrint('[$side Glass] UART TX Characteristic found.');
    } else {
      debugPrint('[$side Glass] UART TX Characteristic not found.');
    }
  }

  void handleNotification(List<int> data) async {
    //String hexData =
    //    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    //debugPrint('[$side Glass] Received data: $hexData');

    // Check for side button press event
    if (data.length >= 2 && data[0] == Commands.BUTTON_PRESS) {
      debugPrint('[$side Glass] Side button pressed');
      // Call the callback if it's defined
      if (onSideButtonPress != null) {
        onSideButtonPress!();
      }
    }

    // Check for battery response (0x2C command)
    if (data.length >= 3 && data[0] == Commands.GET_BATTERY) {
      debugPrint(
        '[$side Glass] Battery response received: ${data.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}',
      );

      // Parse battery info using the protocol parser
      BatteryFrameLog.singleton.record(side, data);

      // The polled reply may also carry the case level. The manager decides
      // whether to believe it: a suspected value never displaces a confirmed
      // one.
      final caseReading = CaseBatteryParser.fromPolledReply(data);
      if (caseReading != null) {
        BluetoothManager.singleton.updateCaseBattery(caseReading);
      }

      final batteryInfo = G1BatteryInfo.fromResponse(data, side);
      if (batteryInfo != null) {
        debugPrint('[$side Glass] Battery parsed: ${batteryInfo.toString()}');
        // Call the battery response callback if it's defined
        if (onBatteryResponse != null) {
          onBatteryResponse!(batteryInfo);
        }
      } else {
        debugPrint('[$side Glass] Failed to parse battery response');
      }
    }

    // Call the receive handler function
    await reciever.receiveHandler(side, data);
  }

  Future<void> sendData(List<int> data) async {
    if (uartTx != null) {
      try {
        if (device.isConnected) {
          await uartTx!.write(data, withoutResponse: false);
          //debugPrint(
          //    'Sent data to $side glass: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        } else {
          debugPrint('Device not connected, cannot send data to $side glass.');
        }
      } catch (e) {
        debugPrint('Error sending data to $side glass: $e');
      }
    } else {
      debugPrint('UART TX not available for $side glass.');
    }
  }

  List<int> _constructHeartbeat(int seq) {
    int length = 6;
    return [
      Commands.HEARTBEAT,
      length & 0xFF,
      (length >> 8) & 0xFF,
      seq % 0xFF,
      0x04,
      seq % 0xFF,
    ];
  }

  /// Send a single heartbeat message to keep the connection alive
  Future<void> sendHeartbeat() async {
    if (device.isConnected) {
      List<int> heartbeatData = _constructHeartbeat(heartbeatSeq++);
      await sendData(heartbeatData);
      debugPrint('[$side Glass] Heartbeat sent (seq: ${heartbeatSeq - 1})');
    }
  }

  /// Set whether heartbeat is managed externally (by background service)
  void setExternalHeartbeatManaged(bool managed) {
    _externalHeartbeatManaged = managed;
    if (managed) {
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
    } else if (device.isConnected) {
      startHeartbeat();
    }
  }

  void startHeartbeat() {
    if (_externalHeartbeatManaged) {
      return; // Don't start internal heartbeat if managed externally
    }

    // Cancel existing timer first to prevent duplicates
    heartbeatTimer?.cancel();
    heartbeatTimer = null;

    const heartbeatInterval = Duration(seconds: 5);
    heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) async {
      if (device.isConnected) {
        try {
          List<int> heartbeatData = _constructHeartbeat(heartbeatSeq++);
          await sendData(heartbeatData);
        } catch (e) {
          debugPrint('[$side Glass] Heartbeat failed: $e');
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Schedule a persistent reconnection attempt with exponential backoff
  /// True while this side is working its way through a reconnect loop.
  ///
  /// Exposed so that nothing else starts a second one. Three separate places
  /// used to react to a disconnection independently, none aware of the
  /// others.
  bool get isReconnecting => _isReconnecting;

  /// How long to wait before the next reconnect attempt.
  ///
  /// Keyed on how long the glasses have been gone rather than on how many
  /// attempts have been made, because that is the thing that actually
  /// predicts the answer. Most disconnections are a second of interference
  /// and resolve immediately; a pair left in the case will not come back for
  /// hours, and polling for them every thirty seconds the whole time is what
  /// drains a phone overnight.
  ///
  /// Attempts in the first hour of absence: about 115. Every hour after
  /// that: 12. Under the previous flat thirty second ceiling it was 120 an
  /// hour, for as long as the app ran — and that was only one of the three
  /// loops then running at once.
  ///
  /// The first half minute is deliberately faster than it used to be.
  /// Stepping out of range and back is the common case and should be
  /// invisible.
  static Duration reconnectDelayFor(Duration sinceDisconnect) {
    if (sinceDisconnect < const Duration(seconds: 30)) {
      return const Duration(seconds: 2);
    }
    if (sinceDisconnect < const Duration(minutes: 2)) {
      return const Duration(seconds: 5);
    }
    if (sinceDisconnect < const Duration(minutes: 10)) {
      return const Duration(seconds: 15);
    }
    if (sinceDisconnect < const Duration(hours: 1)) {
      return const Duration(minutes: 1);
    }
    return const Duration(minutes: 5);
  }

  /// Brings the next attempt forward, for when something suggests the glasses
  /// may be back: the app returning to the foreground, Bluetooth being turned
  /// on again. Without this, a pair picked up after two hours would wait up
  /// to five minutes to be noticed.
  void hurryReconnect() {
    if (!_isReconnecting) return;
    _disconnectedAt = DateTime.now();
  }

  DateTime? _disconnectedAt;

  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _connectRetries = 0;
    _disconnectedAt = DateTime.now();

    Future<void> attemptReconnect() async {
      // No attempt limit.
      //
      // There used to be fifty, which at a thirty second ceiling is about
      // twenty-five minutes — after which the glasses were abandoned for the
      // lifetime of the process. Put them in the case over lunch and they
      // would never come back without restarting the app, which is
      // indistinguishable from the reconnection not existing.
      //
      // Giving up made sense when each attempt was expensive. It is not: a
      // failed BLE connect to an absent device costs a scan window every
      // thirty seconds, and the loop ends the moment someone disconnects on
      // purpose.
      while (_isReconnecting) {
        _connectRetries++;
        final since =
            DateTime.now().difference(_disconnectedAt ?? DateTime.now());
        final delay = reconnectDelayFor(since);
        debugPrint(
          '[$side Glass] Auto-reconnect attempt $_connectRetries in ${delay.inSeconds}s',
        );
        await Future.delayed(delay);

        if (!_isReconnecting) return;

        try {
          await _connectWithRetry();
          // Success
          _connectRetries = 0;
          _isReconnecting = false;
          debugPrint('[$side Glass] Auto-reconnect succeeded');
          onConnectionStateChanged?.call();
          return;
        } catch (e) {
          debugPrint('[$side Glass] Auto-reconnect attempt $_connectRetries failed: $e');
        }
      }
      _isReconnecting = false;
      debugPrint('[$side Glass] Auto-reconnect stopped after $_connectRetries attempts');
    }

    attemptReconnect();
  }

  Future<void> disconnect() async {
    // Stop any ongoing reconnection
    _isReconnecting = false;

    // Cancel all subscriptions and timers first
    await notificationSubscription?.cancel();
    notificationSubscription = null;

    await connectionStateSubscription?.cancel();
    connectionStateSubscription = null;

    heartbeatTimer?.cancel();
    heartbeatTimer = null;

    // Reset state
    _connectRetries = 0;
    uartTx = null;
    uartRx = null;

    // Then disconnect the device
    try {
      if (device.isConnected) {
        await device.disconnect();
      }
    } catch (e) {
      debugPrint('[$side Glass] Error during disconnect: $e');
    }
    debugPrint('[$side Glass] Disconnected and cleaned up');
    onConnectionStateChanged?.call();
  }

  /// Request battery information from the glasses
  /// According to protocol: Command 0x2C, Subcommand 0x01
  Future<void> requestBatteryInfo() async {
    if (!device.isConnected) {
      debugPrint('[$side Glass] Cannot request battery: not connected');
      return;
    }

    try {
      // Construct battery request command: [0x2C, 0x01]
      List<int> batteryCommand = [Commands.GET_BATTERY, 0x01];
      debugPrint(
        '[$side Glass] Requesting battery info: ${batteryCommand.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}',
      );
      await sendData(batteryCommand);
    } catch (e) {
      debugPrint('[$side Glass] Error requesting battery info: $e');
    }
  }
}
