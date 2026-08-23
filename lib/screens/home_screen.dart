import 'dart:async';

import 'package:flutter/material.dart';

import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:g1_extended/models/g1/battery.dart';
import 'package:g1_extended/models/g1/case_battery.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/screens/checklist_screen.dart';
import 'package:g1_extended/screens/dictation_history_screen.dart';
import 'package:g1_extended/screens/notification_history_screen.dart';
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
import 'package:g1_extended/widgets/lens_preview.dart';
import 'package:g1_extended/services/crash_reporter.dart';
import 'package:g1_extended/models/g1/note_slots.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/services/widget_panel.dart';
import 'package:g1_extended/services/speedometer_service.dart';
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

  // What the lens mirror needs: the configured arrangement, and the slot
  // titles from the same plan the glasses are actually sent.
  DashboardMode _dashMode = DashboardMode.dual;
  DashboardPane _dashPane = DashboardPane.notes;
  List<SlotContent> _slots = const [];
  StreamSubscription<void>? _notesChanges;

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

    // The widget's toggle may have changed the preference while this isolate
    // slept with a stale cache of it.
    unawaited(SpeedometerService.singleton.syncWithPreference());

    // And the glasses may have been reconfigured — from their own touchpad,
    // or from a phase when only the cache was answering. Coming back to the
    // foreground is the moment to stop showing yesterday's answer.
    unawaited(_loadGlassesState());

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

    _notesChanges = NotesLibrary.singleton.changes.listen((_) {
      _loadLensMirror();
    });

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

    final modeIndex = cached['dashboardMode']! as int;
    final paneIndex = cached['dashboardPane']! as int;

    if (mounted) {
      setState(() {
        _brightness = cached['brightness']! as int;
        _autoBrightness = cached['brightnessAuto']! as bool;
        _dashMode = DashboardMode
            .values[modeIndex.clamp(0, DashboardMode.values.length - 1)];
        _dashPane = DashboardPane
            .values[paneIndex.clamp(0, DashboardPane.values.length - 1)];
      });
    }

    unawaited(_loadLensMirror());

    if (!_bluetooth.isConnected) return;

    var brightness = await settings.readBrightness();
    final silent = await settings.readSilentMode();

    // Right after the link comes up the firmware sometimes lets the first
    // query time out; one more try three seconds later is what separates
    // "the A appears by itself" from "you have to open the menu".
    if (brightness == null && _bluetooth.isConnected) {
      await Future.delayed(const Duration(seconds: 3));
      brightness = await settings.readBrightness();
    }

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
    _notesChanges?.cancel();
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

  /// The brightness tile is itself the slider.
  ///
  /// The level is painted as a fill behind the tile's content, and dragging
  /// across the tile sets it — force-setting the brightness without a trip
  /// through two screens. Dragging leaves automatic mode, because that is
  /// what touching a manual control means; tapping still opens the display
  /// settings, where automatic comes back.
  double? _brightnessDrag;

  Widget _buildBrightnessTile() {
    final fraction = _brightnessDrag ??
        (_brightness / BrightnessSetting.maxLevel).clamp(0.0, 1.0);
    final radius = BorderRadius.circular(AppMetrics.tileRadius);

    return ClipRRect(
      borderRadius: radius,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject();
          final width = (box is RenderBox) ? box.size.width / 2 : 180.0;
          setState(() {
            _brightnessDrag =
                ((_brightnessDrag ?? fraction) + details.delta.dx / width)
                    .clamp(0.0, 1.0);
          });
        },
        onHorizontalDragEnd: (_) => _commitBrightnessDrag(),
        onHorizontalDragCancel: () => setState(() => _brightnessDrag = null),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.tile),
            // The level itself, as ground rather than as a number alone.
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: const ColoredBox(color: AppColors.tileActive),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => const DisplaySettingsScreen(),
                    ))
                    .then((_) => _loadGlassesState()),
                child: Padding(
                  padding: AppMetrics.tilePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PixelArt(
                        rows: _autoBrightness
                            ? PixelArtwork.sunAuto
                            : PixelArtwork.sun,
                        size: 24,
                        color: AppColors.ink,
                      ),
                      const Spacer(),
                      Text(
                        _brightnessDrag != null
                            ? '${(_brightnessDrag! * 100).round()}%'
                            : _brightnessLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commitBrightnessDrag() async {
    final fraction = _brightnessDrag;
    if (fraction == null) return;

    final setting = BrightnessSetting.fromFraction(fraction, auto: false);
    setState(() {
      _brightness = setting.level;
      _autoBrightness = false;
      _brightnessDrag = null;
    });
    await GlassesSettingsService.singleton.setBrightness(setting);
  }

  Widget _mirrorChip(String text, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.inkFaint, width: 1),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontFamily: AppTheme.technicalFont,
            fontSize: 11,
            letterSpacing: 1.1,
            color: AppColors.inkMuted,
          ),
        ),
      ),
    );
  }

  Future<void> _cycleDashboardMode() async {
    final next = DashboardMode
        .values[(_dashMode.index + 1) % DashboardMode.values.length];
    setState(() => _dashMode = next);
    await GlassesSettingsService.singleton
        .setDashboardLayout(mode: next, pane: _dashPane);
  }

  Future<void> _cycleDashboardPane() async {
    final next = DashboardPane
        .values[(_dashPane.index + 1) % DashboardPane.values.length];
    setState(() => _dashPane = next);
    await GlassesSettingsService.singleton
        .setDashboardLayout(mode: _dashMode, pane: next);
  }

  /// Reads the slot plan — the one the glasses are genuinely written from.
  Future<void> _loadLensMirror() async {
    try {
      final plan = await _bluetooth.noteSlotPlan();
      final slots = [
        for (var slot = 1; slot <= 4; slot++)
          if (plan[slot] != null) plan[slot]!,
      ];
      if (mounted) setState(() => _slots = slots);
    } catch (e) {
      debugPrint('HomeScreen: could not read the slot plan: $e');
    }
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
    // The actions widget shows this too, and a home screen contradicting
    // the app it belongs to is worse than a home screen with no widget.
    unawaited(WidgetPanel.reflectSilent(next));
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
          // The technical face the rest of the interface speaks, spaced the
          // way the section headers are — a humanist serif title over a
          // pixel interface read as two applications sharing a window.
          Text(
            'G1 EXTENDED',
            style: TextStyle(
              fontFamily: AppTheme.technicalFont,
              fontSize: 17,
              letterSpacing: 3,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const PixelArt(rows: PixelArtwork.sliders, size: 24),
            tooltip: 'Settings',
            onPressed: _openGlassesSettings,
          ),
        ],
      ),
    );
  }

  /// The top banner is the lens.
  ///
  /// Same layout, same content, at the display's own 640 by 200
  /// proportions. The slot titles come from the very plan this app writes
  /// to the glasses, so the mirror cannot drift from the real thing; the
  /// line underneath says which mode and pane are doing the arranging.
  Widget _buildHero() {
    final temperature =
        _weather == null ? '--' : _weather!.temperature.round().toString();

    final battery = _bluetooth.batteryStatus;
    final levels = [
      battery.leftBattery?.percentage,
      battery.rightBattery?.percentage,
    ].whereType<int>();
    final batteryLabel =
        levels.isEmpty ? '--' : '${levels.reduce((a, b) => a < b ? a : b)}%';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
      child: Container(
        color: AppColors.tile,
        padding: const EdgeInsets.all(14),
        child: DotMatrix(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LensPreview(
                now: _now,
                temperature: temperature,
                batteryLabel: batteryLabel,
                mode: _dashMode,
                pane: _dashPane,
                slots: _slots,
                nextEvent: _nextEvent,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // The arrangement changes right here, under the very
                  // mirror it rearranges. It used to live two screens deep
                  // in the display settings, which nobody thought to open
                  // to change what the lens shows.
                  _mirrorChip(
                    _dashMode.label,
                    onTap: _cycleDashboardMode,
                  ),
                  if (_dashMode != DashboardMode.minimal) ...[
                    const SizedBox(width: 8),
                    _mirrorChip(
                      _dashPane.label,
                      onTap: _cycleDashboardPane,
                    ),
                  ],
                  const Spacer(),
                  Flexible(
                    child: Text(
                      _nextEvent ?? 'No upcoming event',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.technicalFont,
                        fontSize: 11,
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
                Expanded(child: _buildBrightnessTile()),
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
      _Action(
        pixels: PixelArtwork.bell,
        label: 'Notifications',
        builder: (_) => const NotificationHistoryScreen(),
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
