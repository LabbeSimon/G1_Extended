import 'package:flutter/material.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/quick_notes_service.dart';

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
  final QuickNotesService _notes = QuickNotesService.singleton;

  bool _ready = false;
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
    await _loadSlot(_slot);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadSlot(int slot) async {
    final note = await _notes.read(slot);
    if (!mounted) return;
    setState(() {
      _slot = slot;
      _title.text = note.title;
      _body.text = note.body;
    });
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      _notify('Nothing to send');
      return;
    }

    // Saved either way: the phone keeps the record, and the note is replayed
    // to the glasses as soon as they are back.
    await _notes.save(QuickNote(slot: _slot, title: title, body: body));

    _notify(BluetoothManager.singleton.isConnected
        ? 'Sent to slot $_slot'
        : 'Saved. It will reach the glasses when they reconnect.');
  }

  Future<void> _clear() async {
    await _notes.clear(_slot);
    setState(() {
      _title.clear();
      _body.clear();
    });
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
            onPressed: _ready ? _clear : null,
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
                for (var i = 1; i <= QuickNotesService.slotCount; i++)
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
              onPressed: _ready ? _send : null,
              icon: const Icon(Icons.send),
              label: Text('Send to slot $_slot'),
            ),
          ],
        ),
      ),
    );
  }
}
