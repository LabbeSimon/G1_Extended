import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final enabled = await UpdateService.singleton.isEnabled();
    if (!mounted) return;
    setState(() {
      _version = '${info.version} (${info.buildNumber})';
      _autoCheck = enabled;
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
          ),
          const Divider(),

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
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy'),
            subtitle: const Text('No account, no telemetry.'),
            onTap: () => launchUrl(
              Uri.parse('$repository/blob/main/PRIVACY.md'),
              mode: LaunchMode.externalApplication,
            ),
          ),
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
