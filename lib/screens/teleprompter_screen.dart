import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/services/teleprompter_tracker.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/utils/lc3.dart';

/// How the script advances.
enum ScrollMode {
  voice('Voice', 'Follows what you say'),
  timed('Timed', 'Advances at a set pace'),
  manual('Manual', 'You advance it yourself');

  const ScrollMode(this.label, this.description);

  final String label;
  final String description;
}

/// Puts a script on the lens and moves it along as it is read.
class TeleprompterScreen extends StatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  State<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends State<TeleprompterScreen> {
  /// How often buffered glasses audio is drained into the recogniser.
  static const Duration _drainInterval = Duration(milliseconds: 300);

  final BluetoothManager _bluetooth = BluetoothManager.singleton;
  final TextEditingController _script = TextEditingController();

  ScrollMode _mode = ScrollMode.voice;
  double _pace = 130;

  List<ScriptPage> _pages = const [];
  TeleprompterTracker? _tracker;
  int _page = 0;
  bool _running = false;
  String _heard = '';

  Timer? _timer;
  LiveTranscription? _session;
  StreamSubscription<String>? _transcript;

  @override
  void dispose() {
    _teardown();
    _script.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    if (!_bluetooth.isConnected) {
      _notify('Glasses are not connected');
      return;
    }

    final pages = ScriptPaginator.paginate(_script.text);
    if (pages.isEmpty) {
      _notify('Nothing to read');
      return;
    }

    setState(() {
      _pages = pages;
      _tracker = TeleprompterTracker(_script.text);
      _page = 0;
      _heard = '';
      _running = true;
    });

    await _show(0);

    switch (_mode) {
      case ScrollMode.voice:
        await _startListening();
      case ScrollMode.timed:
        _scheduleNext();
      case ScrollMode.manual:
        break;
    }
  }

  // ------------------------------------------------------------- voice mode

  Future<void> _startListening() async {
    try {
      _session =
          await SpeechRecognitionService.singleton.startLiveTranscription();
    } on SpeechModelMissingException catch (e) {
      _notify(e.toString());
      await _stop();
      return;
    }

    final receiver = BluetoothReciever();
    receiver.voiceCollector.reset();
    receiver.voiceCollector.isRecording = true;
    await _bluetooth.setMicrophone(true);

    _transcript = _session!.text.listen(_onHeard);

    _timer = Timer.periodic(_drainInterval, (_) async {
      final encoded = await receiver.voiceCollector.getAllDataAndReset();
      if (encoded.isEmpty) return;
      final pcm = await LC3.decodeLC3(Uint8List.fromList(encoded));
      if (pcm.isNotEmpty) await _session?.feed(pcm);
    });
  }

  Future<void> _onHeard(String transcript) async {
    final tracker = _tracker;
    if (tracker == null || !_running) return;

    if (mounted) setState(() => _heard = transcript);

    if (tracker.feed(transcript) == null) return;

    // Turn the page once the reader is inside the next one.
    final target = _pages.indexWhere((page) => page.contains(tracker.position));
    if (target < 0) {
      if (tracker.isFinished) await _finish();
      return;
    }
    if (target != _page) await _show(target);
  }

  // ------------------------------------------------------------- timed mode

  void _scheduleNext() {
    _timer?.cancel();
    if (_page >= _pages.length) return;

    final wordCount =
        _pages[_page].endWord - _pages[_page].firstWord;
    final seconds = wordCount / (_pace / 60);
    _timer = Timer(
      Duration(milliseconds: (seconds * 1000).round().clamp(800, 60000)),
      () async {
        if (!_running) return;
        if (_page + 1 >= _pages.length) {
          await _finish();
        } else {
          await _show(_page + 1);
          _scheduleNext();
        }
      },
    );
  }

  // ----------------------------------------------------------------- common

  Future<void> _show(int page) async {
    if (page < 0 || page >= _pages.length) return;
    if (mounted) setState(() => _page = page);
    await _bluetooth.sendPriorityText(_pages[page].text);
  }

  Future<void> _step(int delta) async {
    final next = (_page + delta).clamp(0, _pages.length - 1);
    if (next == _page) return;

    // Moving by hand also moves the reader's place, or voice mode would drag
    // them straight back to where they were.
    _tracker?.seek(_pages[next].firstWord);
    await _show(next);
    if (_mode == ScrollMode.timed) _scheduleNext();
  }

  Future<void> _finish() async {
    await _stop();
    _notify('End of script');
  }

  Future<void> _stop() async {
    await _teardown();
    if (mounted) setState(() => _running = false);
    await _bluetooth.clearGlassesDisplay();
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    _timer = null;

    await _transcript?.cancel();
    _transcript = null;

    await _session?.close();
    _session = null;

    if (_mode == ScrollMode.voice) {
      final receiver = BluetoothReciever();
      receiver.voiceCollector.isRecording = false;
      receiver.voiceCollector.reset();
      await _bluetooth.setMicrophone(false);
    }
  }

  // -------------------------------------------------------------------- ui

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
        SegmentedButton<ScrollMode>(
          segments: [
            for (final mode in ScrollMode.values)
              ButtonSegment(value: mode, label: Text(mode.label)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _mode.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_mode == ScrollMode.timed) ...[
          const SizedBox(height: 8),
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
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    final tracker = _tracker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Page ${_page + 1} of ${_pages.length}  ·  ${_mode.label}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: tracker?.progress ?? (_page + 1) / _pages.length,
          backgroundColor: AppColors.tile,
          color: AppColors.ink,
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              _pages[_page].text,
              style: const TextStyle(fontSize: 20, height: 1.5),
            ),
          ),
        ),
        if (_mode == ScrollMode.voice && _heard.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _heard,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.inkFaint,
                fontStyle: FontStyle.italic,
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
                onPressed: _stop,
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
