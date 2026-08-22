import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:g1_extended/services/battery_frame_log.dart';
import 'package:g1_extended/services/diagnostic_report.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Captures raw battery frames so the undocumented bytes can be identified.
///
/// The case battery is not in the protocol document, and the document's own
/// byte layout for this frame contradicts its sample data. The way to find it
/// is to record frames in states you control and see which byte follows the
/// case: put the glasses in, take them out, plug the case in, unplug it.
class BatteryCaptureScreen extends StatefulWidget {
  const BatteryCaptureScreen({super.key});

  @override
  State<BatteryCaptureScreen> createState() => _BatteryCaptureScreenState();
}

class _BatteryCaptureScreenState extends State<BatteryCaptureScreen> {
  final BatteryFrameLog _log = BatteryFrameLog.singleton;

  /// The states worth capturing, in the order that isolates one variable
  /// at a time.
  static const List<String> _states = [
    'worn, case unplugged',
    'in case, case unplugged',
    'in case, case plugged in',
    'out of case, case plugged in',
    'case empty and plugged in',
  ];

  /// Writes the report, shows what it contains, then hands it to the share
  /// sheet. Nothing leaves until the user picks where it goes.
  Future<void> _export() async {
    final report = await DiagnosticReport.singleton.build();
    if (!mounted) return;

    final frames =
        (report['batteryFrames'] as Map)['frames'] as List;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The file contains:'),
            const SizedBox(height: 12),
            const Text('• app version and package name'),
            const Text('• operating system and its version'),
            const Text('• whether the glasses are connected, and their names'),
            const Text('• battery percentages'),
            Text('• ${frames.length} captured battery frame(s)'),
            const SizedBox(height: 12),
            const Text(
              'No location, no contacts, no audio, no identifier. It is '
              'written to a file and goes only where you send it.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (!(proceed ?? false)) return;

    final file = await DiagnosticReport.singleton.write();
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'G1 Extended diagnostics',
    );
  }

  @override
  Widget build(BuildContext context) {
    final frames = _log.frames;
    final varying = _log.varyingPositions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery frames'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all frames',
            onPressed: frames.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: _log.export()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export as JSON',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(_log.clear),
          ),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            value: _log.enabled,
            title: const Text('Record battery frames'),
            subtitle: const Text(
              'Everything stays on the phone. Nothing is sent anywhere.',
            ),
            onChanged: (value) => setState(() => _log.enabled = value),
          ),
          const Divider(),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Tag what you are doing, then hold that state for a few seconds '
              'so a frame or two lands. Change one thing at a time.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final state in _states)
                  ChoiceChip(
                    label: Text(state, style: const TextStyle(fontSize: 12)),
                    selected: _log.currentNote == state,
                    onSelected: (selected) => setState(
                      () => _log.currentNote = selected ? state : null,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),

          if (varying.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Byte positions that changed across the capture. A byte that '
                'never moves cannot be the case battery.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            for (final entry in varying.entries)
              ListTile(
                dense: true,
                title: Text('${entry.key}: ${entry.value.join(', ')}'),
                subtitle: Text('${entry.value.length} byte(s) varying'),
              ),
            const Divider(height: 32),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              frames.isEmpty
                  ? 'No frames yet. Turn recording on and connect the glasses.'
                  : '${frames.length} frame(s), newest first',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          for (final frame in frames)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Text(
                frame.toString(),
                style: const TextStyle(
                  fontFamily: AppTheme.technicalFont,
                  fontSize: 11,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
