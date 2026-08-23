import 'dart:async';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';

import 'package:g1_extended/theme/app_theme.dart';

class GlassStatus extends StatefulWidget {
  const GlassStatus({super.key});

  @override
  State<GlassStatus> createState() => GlassStatusState();
}

class GlassStatusState extends State<GlassStatus> {
  final BluetoothManager bluetoothManager = BluetoothManager();

  bool isConnected = false;
  bool isScanning = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    _pairingUpdates?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshData() {
    if (!mounted) {
      return;
    }
    setState(() {
      isConnected = bluetoothManager.isConnected;
      isScanning = bluetoothManager.isScanning;
    });
  }

  Future<void> _disconnect() async {
    try {
      await bluetoothManager.disconnectFromGlasses();
      _refreshData();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  StreamSubscription<Map<String, dynamic>?>? _pairingUpdates;

  void _scanAndConnect() {
    try {
      // Progress arrives from the service, where the radio work happens.
      _pairingUpdates ??=
          FlutterBackgroundService().on('pairingUpdate').listen((event) {
        final message = event?['message'] as String?;
        if (message != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        _refreshData();
      });

      bluetoothManager.startScanAndConnect(
        onUpdate: (_) => _refreshData(),
      );
    } catch (e) {
      debugPrint('Error in _scanAndConnect: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The surrounding tile already says whether the glasses are connected and
    // shows their battery, so this is only the action.
    if (isConnected) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _disconnect,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkMuted,
            side: const BorderSide(color: AppColors.tileActive),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
            ),
          ),
          child: const Text('Disconnect'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isScanning ? null : _scanAndConnect,
        child: isScanning
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Scanning'),
                ],
              )
            : const Text('Connect'),
      ),
    );
  }
}
