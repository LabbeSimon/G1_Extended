import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:g1_extended/models/heart_rate.dart';
import 'package:g1_extended/services/heart_rate_service.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Pairing a heart rate sensor — a chest strap, or a watch broadcasting.
///
/// Anything speaking the standard Bluetooth Heart Rate profile appears
/// here; nothing else can. A watch with broadcast turned off is invisible,
/// and listing it anyway would change nothing — the setting lives on the
/// watch.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  final HeartRateService _service = HeartRateService.singleton;

  String? _pairedName;
  bool _scanning = false;
  final Map<String, ScanResult> _found = {};
  StreamSubscription<ScanResult>? _scanSub;
  StreamSubscription<HeartRateMeasurement>? _live;
  HeartRateMeasurement? _reading;

  @override
  void initState() {
    super.initState();
    _load();
    _live = _service.stream.listen((m) {
      if (mounted) setState(() => _reading = m);
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _live?.cancel();
    unawaited(_service.stopScan());
    super.dispose();
  }

  Future<void> _load() async {
    final name = await _service.rememberedName();
    if (!mounted) return;
    setState(() => _pairedName = name);
    if (name != null) unawaited(_service.start());
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _found.clear();
    });
    _scanSub?.cancel();
    _scanSub = _service.scan().listen((result) {
      if (!mounted) return;
      setState(() => _found[result.device.remoteId.str] = result);
    });
    // The scan itself times out after fifteen seconds; mirror that.
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _adopt(ScanResult result) async {
    await _service.stopScan();
    final name = result.device.platformName.isEmpty
        ? 'Heart rate sensor'
        : result.device.platformName;
    await _service.adopt(result.device, name);
    if (!mounted) return;
    setState(() {
      _pairedName = name;
      _scanning = false;
      _found.clear();
    });
  }

  Future<void> _forget() async {
    await _service.forget();
    if (mounted) {
      setState(() {
        _pairedName = null;
        _reading = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paired = _pairedName;
    final reading = _reading;

    return Scaffold(
      appBar: AppBar(title: const Text('Sensors')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'A chest strap, or a watch in broadcast mode — anything '
              'speaking the standard Bluetooth heart rate profile. Once '
              'paired, put {hr} in any card and the number is on the lens.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (paired != null) ...[
            ListTile(
              leading: PixelArt(rows: PixelArtwork.check, size: 18),
              title: Text(paired),
              subtitle: Text(_liveLine(reading)),
              trailing: TextButton(
                onPressed: _forget,
                child: const Text('Forget'),
              ),
            ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonal(
              onPressed: _scanning ? null : _scan,
              child: Text(_scanning ? 'Scanning…' : 'Scan for sensors'),
            ),
          ),
          for (final result in _found.values)
            ListTile(
              leading: PixelArt(rows: PixelArtwork.bell, size: 16),
              title: Text(result.device.platformName.isEmpty
                  ? result.device.remoteId.str
                  : result.device.platformName),
              subtitle: Text('${result.rssi} dBm'),
              onTap: () => _adopt(result),
            ),
          if (_scanning && _found.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_scanning && _found.isEmpty && paired == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Nothing found? On most watches, heart rate broadcast is a '
                'setting to turn on — the watch decides who may listen.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static String _liveLine(HeartRateMeasurement? reading) {
    if (reading == null) return 'Waiting for a reading…';
    final contact = switch (reading.contactDetected) {
      false => '  ·  no skin contact',
      _ => '',
    };
    return '${reading.bpm} bpm$contact';
  }
}
