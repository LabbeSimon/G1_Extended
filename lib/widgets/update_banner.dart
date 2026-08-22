import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:g1_extended/services/update_service.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Shown at the top of the home screen when a newer release exists.
///
/// It offers the release page rather than installing anything: the app is
/// sideloaded, and silently pulling an APK down would be both a permission
/// people should not have to grant and a poor thing to do without asking.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  AvailableUpdate? _update;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final update = await UpdateService.singleton.check();
    if (mounted) setState(() => _update = update);
  }

  Future<void> _open(AvailableUpdate update) async {
    await launchUrl(
      Uri.parse(update.url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _dismiss(AvailableUpdate update) async {
    await UpdateService.singleton.skip(update.version);
    if (mounted) setState(() => _update = null);
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    if (update == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.gutter),
      child: Material(
        color: AppColors.tileActive,
        borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(update),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            child: Row(
              children: [
                const Icon(Icons.arrow_circle_down_outlined,
                    size: 22, color: AppColors.ink),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version ${update.version} available',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Tap to open the release',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.inkMuted),
                  tooltip: 'Skip this version',
                  onPressed: () => _dismiss(update),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
