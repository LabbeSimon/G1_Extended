import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:g1_extended/services/glasses_relay.dart';
import 'package:g1_extended/services/bluetooth_background_service.dart';
import 'package:g1_extended/services/crash_reporter.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Offers the previous session's crash report, and the one action that
/// usually needs doing afterwards.
///
/// A crash leaves the glasses paired to nothing: the link is gone and the
/// app comes back not knowing it. Copying the report is for reporting the
/// fault; reconnecting is for getting on with the day. Both belong here
/// rather than in a settings screen nobody visits after a crash.
Future<void> showCrashReport(BuildContext context, CrashReport report) async {
  final reporter = CrashReporter.singleton;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const PixelArt(rows: PixelArtwork.warning, size: 28),
      title: Text(report.wasNativeKill
          ? 'The app closed without warning'
          : 'The app stopped unexpectedly'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              report.wasNativeKill
                  ? 'Nothing was caught, so the details are thin: the process '
                      'was ended from outside. The log leading up to it is in '
                      'the report.'
                  : 'The details and the log leading up to it are in the '
                      'report.',
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(dialogContext).dividerColor,
                ),
              ),
              child: Text(
                report.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The report holds the app\'s own log and no personal data. '
              'Read it before sending it anywhere.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await reporter.dismiss();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Dismiss'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report.detail));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Report copied')),
            );
          },
          child: const Text('Copy report'),
        ),
        FilledButton(
          onPressed: () async {
            await reporter.dismiss();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            // Through the service, which owns the glasses. Reconnecting
            // from this isolate would attach a second set of handlers to
            // the same shared GATT link — every packet handled twice.
            await BluetoothBackgroundService.start();
            GlassesRelay.reconnect();
          },
          child: const Text('Reconnect'),
        ),
      ],
    ),
  );
}
