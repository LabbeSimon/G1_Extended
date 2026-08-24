import 'package:android_package_manager/android_package_manager.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/navigation_service.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Which apps may put a notification on the glasses.
///
/// Everything is allowed by default; this screen is for taking apps away.
/// The box stores only the exclusions, so an app installed later is allowed
/// without the user having to come back here.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late Box _blocklist;

  List<ApplicationInfo> _apps = [];
  Map<String, String> _names = {};
  String _query = '';
  bool _loading = true;
  bool _navigation = true;
  bool _noteSlot = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _blocklist = Hive.box('notificationBlocklist');
    _navigation = await NavigationService.singleton.isEnabled();
    _noteSlot = await BluetoothManager().isNotificationNoteSlotEnabled();

    try {
      final manager = AndroidPackageManager();
      final installed = await manager.getInstalledApplications() ?? [];

      final names = <String, String>{};
      for (final app in installed) {
        final package = app.packageName;
        if (package == null) continue;
        names[package] = await manager.getApplicationLabel(
              packageName: package,
            ) ??
            package;
      }

      installed.sort((a, b) => (names[a.packageName] ?? '')
          .toLowerCase()
          .compareTo((names[b.packageName] ?? '').toLowerCase()));

      if (!mounted) return;
      setState(() {
        _apps = installed;
        _names = names;
        _loading = false;
      });
    } catch (e) {
      debugPrint('NotificationSettings: could not list apps: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isAllowed(String package) =>
      _blocklist.get(package, defaultValue: false) != true;

  Future<void> _setAllowed(String package, bool allowed) async {
    if (allowed) {
      await _blocklist.delete(package);
    } else {
      await _blocklist.put(package, true);
    }
    setState(() {});
  }

  Future<void> _allowAll() async {
    await _blocklist.clear();
    setState(() {});
  }

  List<ApplicationInfo> get _visible {
    if (_query.isEmpty) return _apps;
    final query = _query.toLowerCase();
    return _apps.where((app) {
      final name = (_names[app.packageName] ?? '').toLowerCase();
      return name.contains(query) ||
          (app.packageName ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _blocklist.keys.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (excluded > 0)
            TextButton(
              onPressed: _allowAll,
              child: const Text('Allow all'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  value: _navigation,
                  title: const Text('Turn-by-turn directions'),
                  subtitle: const Text(
                    'Reads the instruction your navigation app already shows '
                    'and puts it on the lens. Google Maps, Waze, Organic Maps '
                    'and OsmAnd.',
                  ),
                  onChanged: (value) async {
                    await NavigationService.singleton.setEnabled(value);
                    if (mounted) setState(() => _navigation = value);
                  },
                ),
                SwitchListTile(
                  value: _noteSlot,
                  title: const Text('Last notification as a note'),
                  subtitle: const Text(
                    'Keeps the most recent notification readable in a '
                    'dashboard note slot, in addition to the banner.',
                  ),
                  onChanged: (value) async {
                    await BluetoothManager()
                        .setNotificationNoteSlotEnabled(value);
                    if (mounted) setState(() => _noteSlot = value);
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    excluded == 0
                        ? 'Every app reaches the glasses. Turn one off to '
                            'exclude it.'
                        : '$excluded app${excluded > 1 ? 's' : ''} excluded. '
                            'Everything else reaches the glasses.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search apps',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _visible.isEmpty
                      ? const Center(child: Text('No app matches'))
                      : ListView.builder(
                          itemCount: _visible.length,
                          itemBuilder: (context, index) {
                            final app = _visible[index];
                            final package = app.packageName ?? '';
                            return SwitchListTile(
                              value: _isAllowed(package),
                              onChanged: (value) => _setAllowed(package, value),
                              title: Text(
                                _names[package] ?? package,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                package,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
