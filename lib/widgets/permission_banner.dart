import 'package:flutter/material.dart';

import 'package:g1_extended/screens/settings/permissions_screen.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:g1_extended/services/permission_manager.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Says so when the app is missing something it needs to do its job.
///
/// Most of what this app does depends on a permission Android will never
/// grant on its own: forwarding notifications needs a switch buried in system
/// settings, the agenda needs calendar access, and staying connected needs an
/// exemption from battery optimisation. Without them the app looks broken
/// rather than unpermitted — the glasses connect, and then nothing arrives.
///
/// So the gaps are stated on the home screen until they are closed, rather
/// than left for the user to deduce.
class PermissionBanner extends StatefulWidget {
  const PermissionBanner({super.key});

  @override
  State<PermissionBanner> createState() => PermissionBannerState();
}

class PermissionBannerState extends State<PermissionBanner> {
  /// What the app genuinely cannot work without, in the order it matters.
  static const List<AppPermission> _essential = [
    AppPermission.bluetooth,
    AppPermission.calendar,
    AppPermission.batteryOptimization,
  ];

  List<String> _missing = const [];
  bool _notificationsBlocked = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final missing = <String>[];

    for (final id in _essential) {
      if (!await PermissionManager.isGroupGranted(id)) {
        missing.add(PermissionManager.titleFor(id));
      }
    }

    // Notification access is not a runtime permission: it lives in a system
    // settings page and has to be checked separately.
    final hasNotificationAccess =
        await NotificationListenerService.isPermissionGranted();

    if (!mounted) return;
    setState(() {
      _missing = missing;
      _notificationsBlocked = !hasNotificationAccess;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _missing.length + (_notificationsBlocked ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();

    final items = [
      if (_notificationsBlocked) 'Notification access',
      ..._missing,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.gutter),
      child: Material(
        color: AppColors.tileActive,
        borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PermissionsSettingsPage(),
              ),
            );
            await refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const PixelArt(rows: PixelArtwork.lock, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        total == 1
                            ? 'One permission is missing'
                            : '$total permissions are missing',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
