import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:g1_extended/models/g1/battery.dart';
import 'package:g1_extended/models/g1/case_battery.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/screens/checklist_screen.dart';
import 'package:g1_extended/screens/dictation_history_screen.dart';
import 'package:g1_extended/screens/quick_note_screen.dart';
import 'package:g1_extended/screens/settings/display_settings_screen.dart';
import 'package:g1_extended/screens/teleprompter_screen.dart';
import 'package:g1_extended/screens/live_captions_screen.dart';
import 'package:g1_extended/screens/settings/dashboard_screen.dart';
import 'package:g1_extended/screens/settings/permissions_screen.dart';
import 'package:g1_extended/screens/settings_screen.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/glasses_settings_service.dart';
import 'package:g1_extended/services/onboarding_service.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';
import 'package:g1_extended/widgets/crash_dialog.dart';
import 'package:g1_extended/services/crash_reporter.dart';
import 'package:g1_extended/widgets/bento.dart';
import 'package:g1_extended/widgets/pixel_art.dart';
import 'package:g1_extended/widgets/permission_banner.dart';
import 'package:g1_extended/widgets/update_banner.dart';

/// The home screen: a Bento grid over a hero tile that mirrors what the
/// glasses are showing right now.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  final BluetoothManager _bluetooth = BluetoothManager.singleton;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<G1BatteryStatus>? _batterySubscription;
  Timer? _clock;

  DateTime _now = DateTime.now();
  WeatherData? _weather;
  String? _nextEvent;
  bool _silentMode = false;
  CaseBattery? _caseBattery;
  StreamSubscription<CaseBattery>? _caseSubscription;
  int _brightness = 0;
  bool _autoBrightness = false;

  String get _brightnessLabel =>
      _autoBrightness ? 'Auto' : '${(_brightness / BrightnessSetting.maxLevel * 100).round()}%';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving on purpose is what distinguishes a normal exit from a process
    // that was killed. Without this every backgrounding would look like a
    // crash on the next launch.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(CrashReporter.singleton.markCleanExit());
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    // Back in the foreground: this session is running again, so the marker
    // has to go back or a later kill would go unnoticed.
    unawaited(CrashReporter.singleton.markSessionRunning());

    // Whatever the user just did in system settings, this is the moment to
    // act on it: notification access may now be granted, and the banner may
    // now be wrong.
    _bluetooth.retryNotificationListener();

    // After a long absence the reconnect loop settles into checking every few
    // minutes, which is right for glasses left in a drawer and wrong the
    // moment someone picks them up and opens the app. Opening the app is the
    // clearest cue there is.
    _bluetooth.hurryReconnect();
    _permissionBanner.currentState?.refresh();
    _loadNextEvent();
  }

  final GlobalKey<PermissionBannerState> _permissionBanner =
      GlobalKey<PermissionBannerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _wasConnected = _bluetooth.isConnected;
    _connectionSubscription =
        _bluetooth.connectionStatusStream.listen(_onConnectionChanged);
    _caseBattery = _bluetooth.caseBattery;
    _caseSubscription = _bluetooth.caseBatteryStream.listen((reading) {
      if (mounted) setState(() => _caseBattery = reading);
    });
    _batterySubscription =
        _bluetooth.batteryStatusStream.listen((_) => _refresh());

    _loadWeather();
    _loadNextEvent();
    _loadGlassesState();

    // Ask straight away rather than waiting for the next sync: opening the
    // app is exactly when someone wants to know the level.
    if (_bluetooth.isConnected) {
      _bluetooth.requestBatteryInfo().ignore();
    }

    // Nothing used to bring the permission screen up. The glasses would pair
    // and then sit there receiving nothing, which looks like a broken app
    // rather than an unpermitted one.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _offerCrashReport();
      await _offerPermissions();
    });
  }

  /// Shows the previous session's crash, if there was one.
  ///
  /// Before the permission prompt: a crash is the more urgent thing to say,
  /// and stacking two dialogs makes both easy to dismiss without reading.
  Future<void> _offerCrashReport() async {
    final report = CrashReporter.singleton.pending;
    if (report == null || !mounted) return;
    await showCrashReport(context, report);
  }

  Future<void> _offerPermissions() async {
    if (!await OnboardingService.shouldShowPermissionManager()) return;
    if (!mounted) return;

    await OnboardingService.markPermissionManagerShown();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PermissionsSettingsPage()),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _connectionSubscription?.cancel();
    _caseSubscription?.cancel();
    _batterySubscription?.cancel();
    super.dispose();
  }

  /// Whether the glasses were connected the last time we looked.
  ///
  /// Needed because the connection stream fires on every change, and the
  /// interesting one is the transition into being connected.
  bool _wasConnected = false;

  /// Re-reads what the glasses are doing once they are reachable.
  ///
  /// This used to be a bare `setState`. Connection normally completes a
  /// second or two after this screen is built, by which time the initial read
  /// has already given up — so the tiles kept showing cached defaults for the
  /// whole session. Automatic brightness was the visible case: the "Auto"
  /// label only appeared after opening the brightness screen, which queries
  /// the glasses itself.
  void _onConnectionChanged(bool connected) {
    final justConnected = connected && !_wasConnected;
    _wasConnected = connected;

    if (justConnected) {
      // Only on the transition. The battery stream also calls _refresh, and
      // asking the glasses for every setting on each battery packet would put
      // a conversation on the radio for no reason.
      _loadGlassesState();
      _bluetooth.requestBatteryInfo().ignore();
    }

    _refresh();
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
              PermissionBanner(key: _permissionBanner),
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
          const PixelArt(rows: PixelArtwork.glasses, size: 16),
          const SizedBox(width: 14),
          Text(
            'G1 Extended',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const PixelArt(rows: PixelArtwork.sliders, size: 20),
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
                  GlassesBattery(
                    left: battery.leftBattery?.percentage,
                    right: battery.rightBattery?.percentage,
                    charging: battery.isAnyCharging,
                  ),
                  if (_caseBattery != null) ...[
                    const SizedBox(height: 8),
                    CaseBatteryReadout(
                      percentage: _caseBattery!.percentage,
                      suspected: !_caseBattery!.isConfirmed,
                    ),
                  ],
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
                    pixels: _autoBrightness
                        ? PixelArtwork.sunAuto
                        : PixelArtwork.sun,
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
                    pixels: PixelArtwork.moon,
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
        pixels: PixelArtwork.note,
        label: 'Quick note',
        builder: (_) => const QuickNoteScreen(),
      ),
      _Action(
        pixels: PixelArtwork.captions,
        label: 'Live captions',
        builder: (_) => const LiveCaptionsScreen(),
      ),
      _Action(
        pixels: PixelArtwork.list,
        label: 'Teleprompter',
        builder: (_) => const TeleprompterScreen(),
      ),
      _Action(
        pixels: PixelArtwork.mic,
        label: 'Dictation',
        builder: (_) => const DictationHistoryScreen(),
      ),
      _Action(
        pixels: PixelArtwork.check,
        label: 'Checklists',
        builder: (_) => const ChecklistPage(),
      ),
      _Action(
        pixels: PixelArtwork.grid,
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
            pixels: action.pixels,
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
    required this.pixels,
    required this.label,
    required this.builder,
  });

  final List<String> pixels;
  final String label;
  final WidgetBuilder? builder;
}
