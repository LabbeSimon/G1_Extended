import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/battery.dart';
import 'package:g1_extended/screens/settings/about_screen.dart';
import 'package:g1_extended/screens/settings/assistant_screen.dart';
import 'package:g1_extended/screens/settings/clocks_screen.dart';
import 'package:g1_extended/screens/settings/custom_cards_screen.dart';
import 'package:g1_extended/screens/settings/dashboard_screen.dart';
import 'package:g1_extended/screens/settings/notifications_screen.dart';
import 'package:g1_extended/screens/settings/display_settings_screen.dart';
import 'package:g1_extended/screens/settings/speedometer_screen.dart';
import 'package:g1_extended/screens/settings/voice_settings_screen.dart';
import 'package:g1_extended/screens/settings/widget_screen.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';
import 'package:g1_extended/widgets/bento.dart';
import 'package:g1_extended/widgets/pixel_art.dart';
import 'package:g1_extended/widgets/glass_status.dart';

class GlassesSettingsPage extends StatefulWidget {
  const GlassesSettingsPage({super.key});

  @override
  State<GlassesSettingsPage> createState() => _GlassesSettingsPageState();
}

class _GlassesSettingsPageState extends State<GlassesSettingsPage> {
  bool _isGlassesDisplayEnabled = true;
  G1BatteryStatus _batteryStatus = G1BatteryStatus(lastUpdated: DateTime.now());
  StreamSubscription<G1BatteryStatus>? _batterySubscription;
  bool _isConnected = false;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _loadGlassesDisplayPreference();
    if (BluetoothManager.singleton.isConnected) {
      BluetoothManager.singleton.requestBatteryInfo().ignore();
    }
    _startBatteryStatusTracking();
    _startConnectionStatusTracking();
  }

  Future<void> _loadGlassesDisplayPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final preference = prefs.getBool('glasses_display_enabled') ?? true;
    if (!mounted) {
      return;
    }
    setState(() {
      _isGlassesDisplayEnabled = preference;
    });
  }

  Future<void> _saveGlassesDisplayPreference(bool value) async {
    await BluetoothManager.setGlassesDisplayEnabled(value);

    final bluetoothManager = BluetoothManager();

    if (bluetoothManager.isConnected) {
      await bluetoothManager.setSilentMode(!value);

      if (!value) {
        await bluetoothManager.clearGlassesDisplay();
      }
    }
  }

  void _startBatteryStatusTracking() {
    try {
      final bluetoothManager = BluetoothManager();

      _batterySubscription = bluetoothManager.batteryStatusStream.listen(
        (status) {
          if (mounted) {
            setState(() {
              _batteryStatus = status;
            });
          }
        },
        onError: (error) {
          debugPrint('Battery status stream error: $error');
        },
      );

      if (mounted) {
        setState(() {
          _batteryStatus = bluetoothManager.batteryStatus;
        });
      }

      try {
        bluetoothManager.requestBatteryInfo();
      } catch (e) {
        debugPrint('Error requesting battery info in settings: $e');
      }
    } catch (e) {
      debugPrint('Error starting battery status tracking: $e');
    }
  }

  void _startConnectionStatusTracking() {
    final bluetoothManager = BluetoothManager();
    _isConnected = bluetoothManager.isConnected;
    _connectionSubscription = bluetoothManager.connectionStatusStream.listen((
      connected,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isConnected = connected;
      });
    });
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  /// "12s ago", "4m ago" — short enough to sit under a battery reading.
  String _formatRelativeTime(DateTime timestamp) {
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: AppMetrics.pagePadding,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildDeviceTile(),
            const SizedBox(height: AppMetrics.gutter),
            _buildDisplayToggle(),
            const SizedBox(height: AppMetrics.gutter),
            _buildSettingsList(),
            const SizedBox(height: 28),
            _buildVersion(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          Text(
            'Glasses',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 22, fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  /// The device tile: what the glasses are doing, and the one button that
  /// changes it. Everything else on this screen is a setting.
  Widget _buildDeviceTile() {
    final left = _batteryStatus.leftBattery;
    final right = _batteryStatus.rightBattery;
    final charging = _batteryStatus.isAnyCharging;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
      child: Container(
        color: AppColors.tile,
        child: DotMatrix(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PixelArt(
                      rows: PixelArtwork.glasses,
                      size: 18,
                      color:
                          _isConnected ? AppColors.ink : AppColors.inkFaint,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _isConnected ? 'My G1' : 'Not connected',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_isConnected) ...[
                  GlassesBattery(
                    left: left?.percentage,
                    right: right?.percentage,
                    charging: charging,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Updated ${_formatRelativeTime(_batteryStatus.lastUpdated)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Text(
                    'Put both temples in range and pair them.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 18),
                const GlassStatus(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Silent mode reads better as an on/off tile than as a paragraph and a
  /// switch, and it is the control people reach for most often here.
  Widget _buildDisplayToggle() {
    final silent = !_isGlassesDisplayEnabled;

    return BentoTile(
      pixels: silent ? PixelArtwork.moon : PixelArtwork.sun,
      active: silent,
      onTap: () {
        setState(() => _isGlassesDisplayEnabled = silent);
        _saveGlassesDisplayPreference(silent);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            silent ? 'Silent mode on' : 'Display active',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            silent
                ? 'Nothing reaches the lens until you turn this off.'
                : 'The timeline and notifications reach the lens.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList() {
    final entries = <_SettingsEntry>[
      _SettingsEntry(
        pixels: PixelArtwork.sun,
        title: 'Display',
        subtitle: 'Brightness, position in the lens, head-up angle.',
        builder: (_) => const DisplaySettingsScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.grid,
        title: 'Dashboard',
        subtitle: 'What shows on your glasses timeline.',
        builder: (_) => const DashboardSettingsPage(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.note,
        title: 'My cards',
        subtitle: 'Your own lines on the glasses.',
        builder: (_) => const CustomCardsScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.bell,
        title: 'Notifications',
        subtitle: 'Which apps reach the lens.',
        builder: (_) => const NotificationSettingsPage(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.chat,
        title: 'Assistant',
        subtitle: 'Ask a model you host, or one you chose.',
        builder: (_) => const AssistantScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.mic,
        title: 'Voice',
        subtitle: 'Wake word, microphone, offline speech model.',
        builder: (_) => const VoiceSettingsScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.speed,
        title: 'Speed',
        subtitle: 'Live speed readout on the lens.',
        builder: (_) => const SpeedometerScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.grid,
        title: 'Widget',
        subtitle: 'The tile on your phone\'s home screen.',
        builder: (_) => const WidgetScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.clock,
        title: 'World clocks',
        subtitle: 'Other places\' time, in a note slot.',
        builder: (_) => const ClocksScreen(),
      ),
      _SettingsEntry(
        pixels: PixelArtwork.info,
        title: 'About',
        subtitle: 'Version, updates, source code.',
        builder: (_) => const AboutScreen(),
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppMetrics.gutter),
          _buildSettingsRow(entries[i]),
        ],
      ],
    );
  }

  Widget _buildSettingsRow(_SettingsEntry entry) {
    return Material(
      color: AppColors.tile,
      borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: entry.builder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              PixelArt(rows: entry.pixels, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(entry.subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersion() {
    return Center(
      child: Text(
        'G1 Extended',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.inkFaint),
      ),
    );
  }
}

class _SettingsEntry {
  const _SettingsEntry({
    required this.pixels,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final List<String> pixels;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}
