import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';

/// The four note slots the glasses keep on device.
///
/// A note stays on the lens until it is replaced or cleared, which makes this
/// the right place for a shopping list, a door code, or a line you need to
/// remember on stage.
class QuickNoteScreen extends StatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  State<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends State<QuickNoteScreen> {
  /// The hardware exposes exactly four slots, numbered 1 to 4.
  static const int _slotCount = 4;
  static const String _boxName = 'quickNotes';

  final BluetoothManager _bluetooth = BluetoothManager.singleton;

  Box? _box;
  int _slot = 1;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final box =
        Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : await Hive.openBox(_boxName);
    if (!mounted) return;
    setState(() => _box = box);
    _loadSlot(_slot);
  }

  void _loadSlot(int slot) {
    final stored = _box?.get('slot_$slot') as Map?;
    setState(() {
      _slot = slot;
      _title.text = stored?['title'] as String? ?? '';
      _body.text = stored?['body'] as String? ?? '';
    });
  }

  Future<void> _send() async {
    if (!_bluetooth.isConnected) {
      _notify('Glasses are not connected');
      return;
    }

    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      _notify('Nothing to send');
      return;
    }

    await _box?.put('slot_$_slot', {'title': title, 'body': body});

    await _bluetooth.sendNote(
      Note(
        noteNumber: _slot,
        name: title.isEmpty ? 'Note $_slot' : title,
        text: body,
      ),
    );
    _notify('Sent to slot $_slot');
  }

  Future<void> _clear() async {
    await _box?.delete('slot_$_slot');
    setState(() {
      _title.clear();
      _body.clear();
    });

    if (_bluetooth.isConnected) {
      await _bluetooth.sendNote(
        Note(noteNumber: _slot, name: '', text: ''),
      );
    }
    _notify('Slot $_slot cleared');
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear this slot',
            onPressed: _box == null ? null : _clear,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: [
                for (var i = 1; i <= _slotCount; i++)
                  ButtonSegment(value: i, label: Text('$i')),
              ],
              selected: {_slot},
              onSelectionChanged: (selection) => _loadSlot(selection.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _body,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _box == null ? null : _send,
              icon: const Icon(Icons.send),
              label: Text('Send to slot $_slot'),
            ),
          ],
        ),
      ),
    );
  }
}
