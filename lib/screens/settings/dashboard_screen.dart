import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/time_sync.dart';
import 'package:g1_extended/utils/ui_perfs.dart';
import 'package:flutter/material.dart';

import 'package:g1_extended/screens/calendars_screen.dart';
import 'package:g1_extended/screens/checklist_screen.dart';
import 'package:g1_extended/screens/daily_screen.dart';
import 'package:g1_extended/screens/settings/custom_cards_screen.dart';
import 'package:g1_extended/screens/stop_screen.dart';
import 'package:g1_extended/theme/app_theme.dart';

class DashboardSettingsPage extends StatefulWidget {
  const DashboardSettingsPage({super.key});

  @override
  DashboardSettingsPageState createState() => DashboardSettingsPageState();
}

class DashboardSettingsPageState extends State<DashboardSettingsPage> {
  bool _is24HourFormat =
      UiPerfs.singleton.timeFormat == TimeFormat.TWENTY_FOUR_HOUR;
  bool _isFahrenheit =
      UiPerfs.singleton.temperatureUnit == TemperatureUnit.FAHRENHEIT;
  final BluetoothManager _bluetoothManager = BluetoothManager.singleton;
  bool _isUpdatingTime = false;
  bool _isUpdatingTemperature = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _is24HourFormat =
          UiPerfs.singleton.timeFormat == TimeFormat.TWENTY_FOUR_HOUR;
      _isFahrenheit =
          UiPerfs.singleton.temperatureUnit == TemperatureUnit.FAHRENHEIT;
    });
  }

  Future<void> _saveSettingsAndTriggerUpdate() async {
    setState(() {
      _isUpdatingTime = true;
    });

    UiPerfs.singleton.timeFormat =
        _is24HourFormat ? TimeFormat.TWENTY_FOUR_HOUR : TimeFormat.TWELVE_HOUR;

    // Immediately update time format on glasses if connected
    if (_bluetoothManager.isConnected) {
      try {
        await TimeSync.updateTimeAndWeather();
        debugPrint('Time format updated on glasses instantly');

        // Show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_is24HourFormat
                  ? 'Switched to 24-hour format on glasses'
                  : 'Switched to 12-hour format on glasses'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error updating time format on glasses: $e');

        // Show error feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update glasses time format'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Show glasses not connected message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Glasses not connected - format will be updated when connected'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    setState(() {
      _isUpdatingTime = false;
    });

    // Trigger full dashboard sync
    _bluetoothManager.sync();
  }

  Future<void> _saveTemperatureSettingsAndTriggerUpdate() async {
    setState(() {
      _isUpdatingTemperature = true;
    });

    UiPerfs.singleton.temperatureUnit =
        _isFahrenheit ? TemperatureUnit.FAHRENHEIT : TemperatureUnit.CELSIUS;

    // Immediately update temperature unit on glasses if connected
    if (_bluetoothManager.isConnected) {
      try {
        await TimeSync.updateTimeAndWeather();
        debugPrint('Temperature unit updated on glasses instantly');

        // Show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isFahrenheit
                  ? 'Switched to Fahrenheit on glasses'
                  : 'Switched to Celsius on glasses'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error updating temperature unit on glasses: $e');

        // Show error feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update glasses temperature unit'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Show glasses not connected message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Glasses not connected - unit will be updated when connected'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    setState(() {
      _isUpdatingTemperature = false;
    });

    // Trigger full dashboard sync
    _bluetoothManager.sync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'What the glasses show, and how. The four note slots are shared '
              'between everything below, newest and soonest first.',
              style: TextStyle(fontSize: 12),
            ),
          ),

          _header('What it shows'),
          _entry(
            icon: Icons.event_outlined,
            title: 'Calendars',
            subtitle: 'Choose which calendars appear on the glasses.',
            builder: (_) => const CalendarsPage(),
          ),
          _entry(
            icon: Icons.repeat,
            title: 'Routines',
            subtitle: 'Things that happen at the same time every day.',
            builder: (_) => const DailyPage(),
          ),
          _entry(
            icon: Icons.alarm,
            title: 'Reminders',
            subtitle: 'One-off prompts at a set time.',
            builder: (_) => const StopPage(),
          ),
          _entry(
            icon: Icons.checklist_outlined,
            title: 'Checklists',
            subtitle: 'Lists you can tick off from the glasses.',
            builder: (_) => const ChecklistPage(),
          ),
          _entry(
            icon: Icons.edit_note_outlined,
            title: 'My cards',
            subtitle: 'Your own lines, from live values or a web address.',
            builder: (_) => const CustomCardsScreen(),
          ),
          const Divider(height: 32),

          _header('How it reads'),
          SwitchListTile(
            value: _is24HourFormat,
            title: const Text('24-hour clock'),
            subtitle: Text(_is24HourFormat ? '14:30' : '2:30 PM'),
            onChanged: _isUpdatingTime
                ? null
                : (value) {
                    setState(() => _is24HourFormat = value);
                    _saveSettingsAndTriggerUpdate();
                  },
            secondary: _isUpdatingTime
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.schedule),
          ),
          SwitchListTile(
            value: _isFahrenheit,
            title: const Text('Fahrenheit'),
            subtitle: Text(_isFahrenheit ? '70 °F' : '21 °C'),
            onChanged: _isUpdatingTemperature
                ? null
                : (value) {
                    setState(() => _isFahrenheit = value);
                    _saveTemperatureSettingsAndTriggerUpdate();
                  },
            secondary: _isUpdatingTemperature
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.thermostat),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              'The layout itself — full, dual or minimal, and which pane sits '
              'beside the clock — is under Display.',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _entry({
    required IconData icon,
    required String title,
    required String subtitle,
    required WidgetBuilder builder,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: builder)),
      );
}
