import 'package:flutter/material.dart';

import 'package:g1_extended/services/speedometer_service.dart';

/// The live speed readout, and the one honest sentence about what it costs.
class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  final SpeedometerService _speedometer = SpeedometerService.singleton;

  bool _loading = true;
  bool _enabled = false;
  SpeedUnit _unit = SpeedUnit.kmh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _speedometer.isEnabled();
    final unit = await _speedometer.readUnit();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _unit = unit;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Speed')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            value: _enabled,
            title: const Text('Show speed on the glasses'),
            subtitle: const Text(
              'Reads the phone GPS and draws the number on the lens. While '
              'navigating, it rides along on the direction line instead.',
            ),
            onChanged: (value) async {
              await _speedometer.setEnabled(value);
              if (mounted) setState(() => _enabled = value);
            },
          ),
          const Divider(),

          RadioGroup<SpeedUnit>(
            groupValue: _unit,
            onChanged: (unit) async {
              if (unit == null) return;
              await _speedometer.setUnit(unit);
              if (mounted) setState(() => _unit = unit);
            },
            child: const Column(
              children: [
                RadioListTile<SpeedUnit>(
                  value: SpeedUnit.kmh,
                  title: Text('Kilometres per hour'),
                ),
                RadioListTile<SpeedUnit>(
                  value: SpeedUnit.mph,
                  title: Text('Miles per hour'),
                ),
              ],
            ),
          ),
          const Divider(),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'What this costs',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Android will not give a backgrounded app GPS fixes without a '
              'foreground service that declares it uses location, and a speed '
              'that stops when your screen locks would be useless. So while '
              'this is on, the app holds that service and the GPS stays '
              'active, which uses battery.\n\n'
              'The position is turned into a number on your phone. Nothing '
              'about where you are is stored or sent anywhere.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
