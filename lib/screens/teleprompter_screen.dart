import 'dart:async';

import 'package:flutter/material.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Paces a script through the lens, one screenful at a time.
///
/// The glasses hold a limited amount of text, so the script is split into
/// chunks on word boundaries and pushed at a speed the reader sets. The phone
/// keeps the whole script and shows where you are.
class TeleprompterScreen extends StatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  State<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends State<TeleprompterScreen> {
  /// Roughly what fits on the lens without being cut off.
  static const int _charsPerScreen = 180;

  final BluetoothManager _bluetooth = BluetoothManager.singleton;
  final TextEditingController _script = TextEditingController();

  List<String> _chunks = const [];
  int _index = 0;
  Timer? _advanceTimer;

  /// Words per minute the reader is aiming for.
  double _pace = 130;
  bool _running = false;

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _script.dispose();
    super.dispose();
  }

  /// Splits the script on word boundaries so no word is ever cut in half.
  List<String> _split(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || (words.length == 1 && words.first.isEmpty)) {
      return const [];
    }

    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final word in words) {
      if (buffer.isNotEmpty && buffer.length + word.length + 1 > _charsPerScreen) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word);
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());

    return chunks;
  }

  /// How long a chunk stays up, derived from its word count and the pace.
  Duration _holdFor(String chunk) {
    final words = chunk.split(RegExp(r'\s+')).length;
    final seconds = words / (_pace / 60);
    return Duration(milliseconds: (seconds * 1000).round().clamp(800, 30000));
  }

  Future<void> _start() async {
    if (!_bluetooth.isConnected) {
      _notify('Glasses are not connected');
      return;
    }

    final chunks = _split(_script.text);
    if (chunks.isEmpty) {
      _notify('Nothing to read');
      return;
    }

    setState(() {
      _chunks = chunks;
      _index = 0;
      _running = true;
    });

    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    if (!_running || _index >= _chunks.length) return;

    final chunk = _chunks[_index];
    await _bluetooth.sendPriorityText(chunk);

    _advanceTimer?.cancel();
    _advanceTimer = Timer(_holdFor(chunk), () {
      if (!_running) return;
      if (_index + 1 >= _chunks.length) {
        _stop(finished: true);
      } else {
        setState(() => _index++);
        _showCurrent();
      }
    });
  }

  Future<void> _step(int delta) async {
    if (!_running) return;
    final next = (_index + delta).clamp(0, _chunks.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
    await _showCurrent();
  }

  Future<void> _stop({bool finished = false}) async {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (mounted) setState(() => _running = false);
    await _bluetooth.clearGlassesDisplay();
    if (finished) _notify('End of script');
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teleprompter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _running ? _buildRunning() : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _script,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Paste or type your script…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Pace'),
            Expanded(
              child: Slider(
                value: _pace,
                min: 60,
                max: 220,
                divisions: 16,
                onChanged: (value) => setState(() => _pace = value),
              ),
            ),
            Text('${_pace.round()} wpm'),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Screen ${_index + 1} of ${_chunks.length}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_index + 1) / _chunks.length,
          backgroundColor: AppColors.tile,
          color: AppColors.ink,
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              _chunks[_index],
              style: const TextStyle(fontSize: 20, height: 1.5),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: IconButton.filled(
                onPressed: () => _step(-1),
                icon: const Icon(Icons.skip_previous),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => _stop(),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IconButton.filled(
                onPressed: () => _step(1),
                icon: const Icon(Icons.skip_next),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
