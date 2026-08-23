import 'package:flutter/material.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/world_clocks.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// The extra time zones shown on the lens.
///
/// The glasses already show local time in their header; this list holds the
/// elsewhere — up to four, the lines a note slot can carry.
class ClocksScreen extends StatefulWidget {
  const ClocksScreen({super.key});

  @override
  State<ClocksScreen> createState() => _ClocksScreenState();
}

class _ClocksScreenState extends State<ClocksScreen> {
  final WorldClocksService _service = WorldClocksService.singleton;

  List<WorldClock> _clocks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clocks = await _service.clocks();
    if (!mounted) return;
    setState(() {
      _clocks = clocks;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await _service.save(_clocks);
    // Straight to the lens, not at the next sync a minute away: adding a
    // clock and seeing nothing happen reads as the feature not working.
    await BluetoothManager.singleton.writeNoteSlots();
  }

  Future<void> _add() async {
    final taken = {for (final c in _clocks) c.zoneId};
    final choices = WorldClocksService.suggestions.entries
        .where((e) => !taken.contains(e.value))
        .toList();

    final picked = await showModalBottomSheet<MapEntry<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListView(
        children: [
          for (final entry in choices)
            ListTile(
              title: Text(entry.key),
              subtitle: Text(entry.value),
              onTap: () => Navigator.of(sheet).pop(entry),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _clocks = [
        ..._clocks,
        WorldClock(label: picked.key, zoneId: picked.value),
      ];
    });
    await _persist();
  }

  Future<void> _remove(WorldClock clock) async {
    setState(() {
      _clocks = [for (final c in _clocks) if (c.zoneId != clock.zoneId) c];
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final full = _clocks.length >= WorldClocksService.maxClocks;

    return Scaffold(
      appBar: AppBar(title: const Text('World clocks')),
      floatingActionButton: full
          ? null
          : FloatingActionButton(
              onPressed: _add,
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clocks.isEmpty
              ? const _Empty()
              : ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        'Shown on the lens as one note, four lines at most. '
                        'Times follow each place\'s own summer time — never a '
                        'fixed offset, which is wrong twice a year.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    for (final clock in _clocks)
                      Dismissible(
                        key: ValueKey(clock.zoneId),
                        direction: DismissDirection.endToStart,
                        background: const ColoredBox(
                          color: Colors.transparent,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 24),
                              child: Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                        onDismissed: (_) => _remove(clock),
                        child: ListTile(
                          leading:
                              PixelArt(rows: PixelArtwork.clock, size: 18),
                          title: Text(clock.label),
                          subtitle: Text(
                            WorldClocksService.formatLine(
                                    clock, DateTime.now()) ??
                                clock.zoneId,
                          ),
                        ),
                      ),
                  ],
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
              PixelArt(rows: PixelArtwork.clock, size: 48),
              SizedBox(height: 16),
              Text(
                'No extra clocks.\n\nAdd up to four places and their local '
                'time appears on the glasses, in a note slot.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
