import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:g1_extended/models/g1/battery.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/screens/checklist_screen.dart';
import 'package:g1_extended/screens/dictation_history_screen.dart';
import 'package:g1_extended/screens/quick_note_screen.dart';
import 'package:g1_extended/screens/settings/display_settings_screen.dart';
import 'package:g1_extended/screens/teleprompter_screen.dart';
import 'package:g1_extended/screens/live_captions_screen.dart';
import 'package:g1_extended/screens/settings/dashboard_screen.dart';
import 'package:g1_extended/screens/settings_screen.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/glasses_settings_service.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/bento.dart';
import 'package:g1_extended/widgets/update_banner.dart';

/// The home screen: a Bento grid over a hero tile that mirrors what the
/// glasses are showing right now.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BluetoothManager _bluetooth = BluetoothManager.singleton;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<G1BatteryStatus>? _batterySubscription;
  Timer? _clock;

  DateTime _now = DateTime.now();
  WeatherData? _weather;
  String? _nextEvent;
  bool _silentMode = false;
  int _brightness = 0;
  bool _autoBrightness = false;

  String get _brightnessLabel =>
      _autoBrightness ? 'Auto' : '${(_brightness / BrightnessSetting.maxLevel * 100).round()}%';

  @override
  void initState() {
    super.initState();

    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _connectionSubscription =
        _bluetooth.connectionStatusStream.listen((_) => _refresh());
    _batterySubscription =
        _bluetooth.batteryStatusStream.listen((_) => _refresh());

    _loadWeather();
    _loadNextEvent();
    _loadGlassesState();
  }

  /// Reads brightness and silent mode back from the glasses, so the tiles
  /// show what the hardware is actually doing rather than what we last sent.
  Future<void> _loadGlassesState() async {
    final settings = GlassesSettingsService.singleton;
    final cached = await settings.cachedValues();

    if (mounted) {
      setState(() {
        _brightness = cached['brightness']! as int;
        _autoBrightness = cached['brightnessAuto']! as bool;
      });
    }

    if (!_bluetooth.isConnected) return;

    final brightness = await settings.readBrightness();
    final silent = await settings.readSilentMode();

    if (!mounted) return;
    setState(() {
      if (brightness != null) {
        _brightness = brightness.level;
        _autoBrightness = brightness.auto;
      }
      if (silent != null) _silentMode = silent;
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _connectionSubscription?.cancel();
    _batterySubscription?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWeather() async {
    final weather = await OpenMeteoWeatherService().getCurrentWeather();
    if (mounted) setState(() => _weather = weather);
  }

  Future<void> _loadNextEvent() async {
    try {
      final dashboard = GlassesDashboard();
      await dashboard.initialize();
      final items = dashboard.items;
      if (!mounted) return;
      setState(() => _nextEvent = items.isEmpty ? null : items.first.title);
    } catch (e) {
      debugPrint('HomeScreen: could not read the dashboard: $e');
    }
  }

  Future<void> _openGlassesSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GlassesSettingsPage()),
    );
    _refresh();
  }

  Future<void> _toggleSilentMode() async {
    if (!_bluetooth.isConnected) return;
    final next = !_silentMode;
    await GlassesSettingsService.singleton.setSilentMode(next);
    if (mounted) setState(() => _silentMode = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadWeather();
            await _loadNextEvent();
          },
          child: ListView(
            padding: AppMetrics.pagePadding,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              const UpdateBanner(),
              _buildHero(),
              const SizedBox(height: AppMetrics.gutter),
              _buildDeviceRow(),
              const SizedBox(height: AppMetrics.gutter),
              _buildActionGrid(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.dashboard_outlined, size: 22, color: AppColors.ink),
          const SizedBox(width: 12),
          Text(
            'G1 Extended',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.ink),
            tooltip: 'Settings',
            onPressed: _openGlassesSettings,
          ),
        ],
      ),
    );
  }

  /// Mirrors the glasses display: the same clock, weather and agenda the
  /// wearer sees, so the phone and the glasses never disagree.
  Widget _buildHero() {
    final temperature = _weather == null
        ? '--'
        : _weather!.temperature.round().toString();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
      child: Container(
        color: AppColors.tile,
        height: 210,
        child: DotMatrix(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Readout(
                            value: DateFormat('EEE, dd/MM').format(_now),
                            muted: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('HH:mm').format(_now),
                            style: Theme.of(context).textTheme.displayLarge,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Readout(
                          value: temperature,
                          unit: 'c',
                          icon: (_weather?.isDay ?? true)
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          muted: true,
                        ),
                        const SizedBox(height: 6),
                        const Readout(
                          value: '0',
                          icon: Icons.notifications_none,
                          muted: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.inkFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nextEvent ?? 'No upcoming event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.technicalFont,
                          fontSize: 13,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Left: the glasses themselves. Right: the two switches worth one tap.
  Widget _buildDeviceRow() {
    final battery = _bluetooth.batteryStatus;
    final connected = _bluetooth.isConnected;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BentoTile(
              onTap: _openGlassesSettings,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'My G1' : 'Not connected',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  Readout(
                    value: battery.leftBattery == null
                        ? '--%'
                        : '${battery.leftBattery!.percentage}%',
                    icon: Icons.battery_std_outlined,
                    muted: !connected,
                  ),
                  const SizedBox(height: 6),
                  Readout(
                    value: battery.rightBattery == null
                        ? '--%'
                        : '${battery.rightBattery!.percentage}%',
                    icon: Icons.battery_std_outlined,
                    muted: !connected,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    connected ? 'Tap to manage' : 'Tap to pair',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.gutter),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BentoTile(
                    icon: _autoBrightness
                        ? Icons.brightness_auto_outlined
                        : Icons.brightness_medium_outlined,
                    label: _brightnessLabel,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => const DisplaySettingsScreen(),
                        ))
                        .then((_) => _loadGlassesState()),
                  ),
                ),
                const SizedBox(height: AppMetrics.gutter),
                Expanded(
                  child: BentoTile(
                    icon: Icons.nightlight_outlined,
                    label: 'Silent mode',
                    active: _silentMode,
                    onTap: connected ? _toggleSilentMode : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    final actions = <_Action>[
      _Action(
        icon: Icons.edit_note_outlined,
        label: 'Quick note',
        builder: (_) => const QuickNoteScreen(),
      ),
      _Action(
        icon: Icons.subtitles_outlined,
        label: 'Live captions',
        builder: (_) => const LiveCaptionsScreen(),
      ),
      _Action(
        icon: Icons.format_list_numbered,
        label: 'Teleprompter',
        builder: (_) => const TeleprompterScreen(),
      ),
      _Action(
        icon: Icons.mic_none_outlined,
        label: 'Dictation',
        builder: (_) => const DictationHistoryScreen(),
      ),
      _Action(
        icon: Icons.checklist_outlined,
        label: 'Checklists',
        builder: (_) => const ChecklistPage(),
      ),
      _Action(
        icon: Icons.view_agenda_outlined,
        label: 'Dashboard',
        builder: (_) => const DashboardSettingsPage(),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppMetrics.gutter,
      crossAxisSpacing: AppMetrics.gutter,
      childAspectRatio: 1.05,
      children: [
        for (final action in actions)
          BentoTile(
            icon: action.icon,
            label: action.label,
            onTap: action.builder == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: action.builder!),
                    ),
          ),
      ],
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder? builder;
}
