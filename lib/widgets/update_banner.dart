import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:g1_extended/services/apk_installer.dart';
import 'package:g1_extended/services/update_service.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Shown at the top of the home screen when a newer release exists.
///
/// One tap downloads the APK and opens Android's install sheet — the system
/// confirms every install itself, that part cannot and should not be
/// skipped. Nothing is downloaded before the tap, and the release page
/// stays a long-press away for anyone who wants to read first.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  AvailableUpdate? _update;

  /// Null when idle; 0..1 while the APK is coming down.
  double? _progress;

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

  Future<void> _install(AvailableUpdate update) async {
    if (_progress != null) return;

    // No APK on the release, or an older Android: the page is all there is.
    if (update.apkUrl == null) return _open(update);

    // The per-app "install unknown apps" switch has to be on first, and
    // only a settings page can turn it on. Asking before downloading spares
    // a 60 MB download that would end at a refusal.
    if (!await ApkInstaller.canInstall()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('One switch first'),
          content: const Text(
            'Android only lets an app offer installs once you allow it, on '
            'a settings page it will open. Allow G1 Extended there, come '
            'back, and tap the update again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (go == true) await ApkInstaller.openInstallPermission();
      return;
    }

    setState(() => _progress = 0);
    final file = await UpdateService.singleton.downloadApk(
      update,
      onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      },
    );
    if (!mounted) return;
    setState(() => _progress = null);

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The download failed. The release page still works.'),
      ));
      return;
    }

    await ApkInstaller.install(file.path);
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
          onTap: () => _install(update),
          onLongPress: () => _open(update),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            child: Row(
              children: [
                const PixelArt(rows: PixelArtwork.download, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version ${update.version} available',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      if (_progress != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _progress == 0 ? null : _progress,
                            minHeight: 4,
                            backgroundColor: AppColors.tile,
                            color: AppColors.ink,
                          ),
                        ),
                      ] else
                        Text(
                          update.apkUrl != null
                              ? 'Tap to download and install'
                              : 'Tap to open the release',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
