import 'package:flutter/material.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/notification_history.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// What arrived while you were not looking.
///
/// The lens shows a notification once and moves on; tapping the left temple
/// walks back through the same list this screen shows. Here it can actually
/// be read — and a tap sends any entry back to the lens, which is the same
/// act as the temple tap, just aimed.
class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final NotificationHistory _history = NotificationHistory.singleton;

  @override
  void initState() {
    super.initState();
    // This screen lives in the interface isolate; the notifications may
    // have been recorded in the other. Load the shared mirror first.
    _history.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _sendToGlasses(RecalledNotification item) async {
    final bluetooth = BluetoothManager.singleton;
    if (bluetooth.isConnected != true) {
      _say('The glasses are not connected');
      return;
    }

    try {
      await bluetooth.sendPriorityText(item.forGlasses());
      _say('On the lens');
    } catch (e) {
      _say('Could not reach the glasses');
      debugPrint('NotificationHistoryScreen: send failed: $e');
    }
  }

  void _clear() {
    setState(_history.clear);
    _say('History cleared');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// "now", "4m", "2h", "1d" — the lens spells these out, but a list column
  /// wants them narrow.
  static String _age(DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return 'now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h';
    return '${elapsed.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final items = _history.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: items.isEmpty
          ? const _Empty()
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: PixelArt(rows: PixelArtwork.bell, size: 18),
                  title: Text(
                    [item.app, item.title]
                        .where((p) => p.trim().isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _age(item.at),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => _sendToGlasses(item),
                );
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelArt(rows: PixelArtwork.bell, size: 48),
              SizedBox(height: 16),
              Text(
                'Nothing yet.\n\nNotifications are kept here for six hours. '
                'Tap the left temple to call the latest back onto the lens; '
                'tap again to walk further back.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
