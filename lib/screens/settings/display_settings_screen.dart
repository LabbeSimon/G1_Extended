import 'package:flutter/material.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/glasses_settings_service.dart';

/// Everything about how the lens renders: brightness, where the text sits,
/// and how far you have to look up before it appears.
class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key});

  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  final GlassesSettingsService _settings = GlassesSettingsService.singleton;

  bool _loading = true;
  bool _applyingPosition = false;
  bool _calibrating = false;

  int _brightness = 20;
  bool _autoBrightness = false;
  int _headUpAngle = 30;
  int _height = 4;
  int _depth = 5;
  bool _wearDetection = true;
  DashboardMode _mode = DashboardMode.dual;
  DashboardPane _pane = DashboardPane.notes;

  bool get _connected => BluetoothManager.singleton.isConnected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Draws cached values immediately, then corrects them with whatever the
  /// glasses actually report.
  Future<void> _load() async {
    final cached = await _settings.cachedValues();
    if (!mounted) return;
    setState(() {
      _brightness = cached['brightness']! as int;
      _autoBrightness = cached['brightnessAuto']! as bool;
      _headUpAngle = cached['headUpAngle']! as int;
      _height = cached['displayHeight']! as int;
      _depth = cached['displayDepth']! as int;
      _wearDetection = cached['wearDetection']! as bool;
      _mode = DashboardMode.values[cached['dashboardMode']! as int];
      _pane = DashboardPane.values[cached['dashboardPane']! as int];
      _loading = false;
    });

    if (!_connected) return;

    final brightness = await _settings.readBrightness();
    final angle = await _settings.readHeadUpAngle();
    final position = await _settings.readDisplayPosition();
    final wear = await _settings.readWearDetection();

    if (!mounted) return;
    setState(() {
      if (brightness != null) {
        _brightness = brightness.level;
        _autoBrightness = brightness.auto;
      }
      if (angle != null) _headUpAngle = angle.degrees;
      if (position != null) {
        _height = position.height;
        _depth = position.depth;
      }
      if (wear != null) _wearDetection = wear;
    });
  }

  Future<void> _applyBrightness() => _settings.setBrightness(
        BrightnessSetting(level: _brightness, auto: _autoBrightness),
      );

  /// The glasses need a preview window before they accept a new position,
  /// so this blocks the controls for a few seconds while it runs.
  Future<void> _applyPosition() async {
    setState(() => _applyingPosition = true);
    try {
      await _settings.setDisplayPosition(
        DisplayPosition(height: _height, depth: _depth),
      );
    } finally {
      if (mounted) setState(() => _applyingPosition = false);
    }
  }

  Future<void> _calibrate() async {
    setState(() => _calibrating = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Look straight ahead, then confirm on the touchpad'),
        duration: Duration(seconds: 6),
      ),
    );

    final confirmed = await _settings.calibrateZeroAngle();
    if (!mounted) return;

    setState(() => _calibrating = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(confirmed
            ? 'Level calibrated'
            : 'Calibration was not confirmed on the glasses'),
      ));
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore defaults?'),
        content: const Text(
          'Brightness, layout, position, head-up angle and wear detection go '
          'back to their starting values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) return;

    setState(() => _applyingPosition = true);
    try {
      await _settings.restoreDefaults();
    } finally {
      if (mounted) setState(() => _applyingPosition = false);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Display')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!_connected)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Glasses are not connected. Changes are saved and applied '
                'the next time they pair.',
              ),
            ),

          _header('Brightness'),
          SwitchListTile(
            value: _autoBrightness,
            title: const Text('Automatic'),
            subtitle: const Text('The glasses follow ambient light.'),
            onChanged: (value) {
              setState(() => _autoBrightness = value);
              _applyBrightness();
            },
          ),
          ListTile(
            enabled: !_autoBrightness,
            title: const Text('Level'),
            subtitle: Slider(
              value: _brightness.toDouble(),
              min: 0,
              max: BrightnessSetting.maxLevel.toDouble(),
              divisions: BrightnessSetting.maxLevel,
              onChanged: _autoBrightness
                  ? null
                  : (value) => setState(() => _brightness = value.round()),
              onChangeEnd: _autoBrightness ? null : (_) => _applyBrightness(),
            ),
            trailing: Text('$_brightness'),
          ),
          const Divider(),

          _header('Layout'),
          ListTile(
            title: const Text('Dashboard'),
            subtitle: Text(_mode.label),
            trailing: DropdownButton<DashboardMode>(
              value: _mode,
              underline: const SizedBox.shrink(),
              items: [
                for (final mode in DashboardMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() => _mode = mode);
                _settings.setDashboardLayout(mode: mode, pane: _pane);
              },
            ),
          ),
          if (_mode.hasSecondaryPane)
            ListTile(
              title: const Text('Second pane'),
              subtitle: Text(_pane.label),
              trailing: DropdownButton<DashboardPane>(
                value: _pane,
                underline: const SizedBox.shrink(),
                items: [
                  for (final pane in DashboardPane.values)
                    DropdownMenuItem(value: pane, child: Text(pane.label)),
                ],
                onChanged: (pane) {
                  if (pane == null) return;
                  setState(() => _pane = pane);
                  _settings.setDashboardLayout(mode: _mode, pane: pane);
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Minimal shows the time alone. Full and Dual add a second pane.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          _header('Position in the lens'),
          ListTile(
            title: const Text('Height'),
            subtitle: Slider(
              value: _height.toDouble(),
              min: DisplayPosition.minHeight.toDouble(),
              max: DisplayPosition.maxHeight.toDouble(),
              divisions: DisplayPosition.maxHeight - DisplayPosition.minHeight,
              onChanged: _applyingPosition
                  ? null
                  : (value) => setState(() => _height = value.round()),
            ),
            trailing: Text('$_height'),
          ),
          ListTile(
            title: const Text('Depth'),
            subtitle: Slider(
              value: _depth.toDouble(),
              min: DisplayPosition.minDepth.toDouble(),
              max: DisplayPosition.maxDepth.toDouble(),
              divisions: DisplayPosition.maxDepth - DisplayPosition.minDepth,
              onChanged: _applyingPosition
                  ? null
                  : (value) => setState(() => _depth = value.round()),
            ),
            trailing: Text('$_depth'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton(
              onPressed: _connected && !_applyingPosition ? _applyPosition : null,
              child: Text(
                _applyingPosition ? 'Look at the lens…' : 'Preview and apply',
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'The glasses only accept these two while in debug mode, which '
              'is switched on for the length of the change and off again '
              'afterwards. They show the new position for a few seconds '
              'before committing to it.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          _header('Head-up activation'),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Calibrate level'),
            subtitle: const Text(
              'Sets the reference the angle is measured from. Without it, the '
              'angle counts from wherever the glasses last thought level was.',
            ),
            enabled: _connected && !_calibrating,
            trailing: _calibrating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _connected && !_calibrating ? _calibrate : null,
          ),
          ListTile(
            title: const Text('Angle'),
            subtitle: Slider(
              value: _headUpAngle.toDouble(),
              min: 0,
              max: HeadUpAngle.maxDegrees.toDouble(),
              divisions: HeadUpAngle.maxDegrees,
              onChanged: (value) =>
                  setState(() => _headUpAngle = value.round()),
              onChangeEnd: (_) =>
                  _settings.setHeadUpAngle(HeadUpAngle(_headUpAngle)),
            ),
            trailing: Text('$_headUpAngle°'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'How far you tilt your head up before the display wakes.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          _header('Wear detection'),
          SwitchListTile(
            value: _wearDetection,
            title: const Text('Detect when taken off'),
            subtitle: const Text('The display sleeps when you remove them.'),
            onChanged: (value) {
              setState(() => _wearDetection = value);
              _settings.setWearDetection(value);
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear the display'),
            enabled: _connected,
            onTap: _settings.clearScreen,
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Restore defaults'),
            subtitle: const Text('Every setting on this screen.'),
            enabled: _connected && !_applyingPosition,
            onTap: _connected ? _restoreDefaults : null,
          ),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
