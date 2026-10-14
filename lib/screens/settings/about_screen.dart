import 'package:flutter/material.dart';
import 'package:g1_extended/services/settings_backup.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:g1_extended/screens/settings/battery_capture_screen.dart';
import 'package:g1_extended/screens/settings/debug_screen.dart';
import 'package:g1_extended/services/developer_mode.dart';
import 'package:g1_extended/services/update_service.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Version, update checking, and the links worth having.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String repository = 'https://github.com/LabbeSimon/G1_Extended';

  String _version = '…';
  bool _autoCheck = true;
  bool _beta = false;
  bool _checking = false;
  bool _developer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final enabled = await UpdateService.singleton.isEnabled();
    final beta = await UpdateService.singleton.isBeta();
    final developer = await DeveloperMode.singleton.isEnabled();
    if (!mounted) return;
    setState(() {
      _version = '${info.version} (${info.buildNumber})';
      _autoCheck = enabled;
      _beta = beta;
      _developer = developer;
    });
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final update = await UpdateService.singleton.check(force: true);
    if (!mounted) return;
    setState(() => _checking = false);

    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are on the latest version')),
      );
      return;
    }

    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Version ${update.version}'),
        content: SingleChildScrollView(
          child: Text(update.notes ?? 'A newer release is available.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open release'),
          ),
        ],
      ),
    );

    if (open ?? false) {
      await launchUrl(Uri.parse(update.url),
          mode: LaunchMode.externalApplication);
    }
  }

  /// Ten taps on the version, the way Android does it.
  Future<void> _tapVersion() async {
    final outcome = await DeveloperMode.singleton.registerTap();
    if (!mounted) return;

    if (outcome.unlocked) setState(() => _developer = true);

    final message = outcome.message;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 900),
        ));
    }
  }

  Future<void> _disableDeveloper() async {
    await DeveloperMode.singleton.setEnabled(false);
    if (mounted) setState(() => _developer = false);
  }

  Future<void> _restoreFromClipboard(BuildContext context) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text ?? '';
    if (!context.mounted) return;

    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The clipboard is empty. Copy your backup first.'),
      ));
      return;
    }

    // Restoring overwrites; that deserves one plain question.
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Restore over current settings?'),
        content: const Text(
          'What is in the backup replaces what is on the phone where the '
          'two disagree. Nothing is deleted that the backup does not name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    try {
      final summary = await SettingsBackup.restore(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(summary)));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: const Text('G1 Extended'),
            subtitle: Text('Version $_version'),
            onTap: _tapVersion,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'An independent companion for the Even Realities G1 — not '
              'made by, affiliated with, or endorsed by Even Realities.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          SwitchListTile(
            value: _beta,
            title: const Text('Beta channel'),
            subtitle: const Text(
              'Offers pre-releases as they are cut. They compile and pass '
              'their tests, but have not been worn on a face — and half of '
              'this app talks to hardware. Turning this on is volunteering.',
            ),
            onChanged: (value) async {
              await UpdateService.singleton.setBeta(value);
              if (!mounted) return;
              setState(() => _beta = value);
              _checkNow();
            },
          ),
          SwitchListTile(
            value: _autoCheck,
            title: const Text('Check for updates'),
            subtitle: const Text(
              'Asks GitHub once every 12 hours whether a newer release exists. '
              'Nothing about you is sent, and nothing installs on its own.',
            ),
            onChanged: (value) async {
              await UpdateService.singleton.setEnabled(value);
              if (mounted) setState(() => _autoCheck = value);
            },
          ),
          ListTile(
            leading: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            title: const Text('Check now'),
            enabled: !_checking,
            onTap: _checking ? null : _checkNow,
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('github.com/LabbeSimon/G1_Extended'),
            onTap: () => launchUrl(Uri.parse(repository),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            subtitle: const Text(
                'Unofficial, free, nothing for sale, your installs are '
                'your call.'),
            onTap: () => launchUrl(
              Uri.parse('$repository/blob/main/TERMS.md'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy'),
            subtitle: const Text('No account, no telemetry.'),
            onTap: () => launchUrl(
              Uri.parse('$repository/blob/main/PRIVACY.md'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Licence'),
            subtitle: const Text('BSD 2-Clause'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'G1 Extended',
              applicationVersion: _version,
              applicationLegalese:
                  'BSD 2-Clause. Copyright (c) 2024, even-realities.\n\n'
                  'Derived from AGiXT/mobile, with the AI assistant and '
                  'everything unrelated to the glasses removed. The Bluetooth '
                  'layer and the LC3 decoder are inherited work.',
            ),
          ),
          if (_developer) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'DEVELOPER OPTIONS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.battery_unknown_outlined),
              title: const Text('Battery frame capture'),
              subtitle: const Text(
                'Record raw protocol frames and export them as JSON.',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BatteryCaptureScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Protocol test bench'),
              subtitle: const Text(
                'Send text, notifications, images and layouts by hand.',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('Export my settings'),
              subtitle: const Text(
                'Everything to the clipboard as JSON — notes, cards, '
                'preferences. Paste it somewhere safe.',
              ),
              onTap: () async {
                final backup = await SettingsBackup.export();
                await Clipboard.setData(ClipboardData(text: backup));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Backup copied. Paste it somewhere safe — '
                        'a note, a file, an email to yourself.'),
                  ));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('Restore my settings'),
              subtitle:
                  const Text('From a backup copied to the clipboard.'),
              onTap: () => _restoreFromClipboard(context),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Turn off developer options'),
              onTap: _disableDeveloper,
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Companion app for Even Realities G1 glasses. Not affiliated '
              'with Even Realities.',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
