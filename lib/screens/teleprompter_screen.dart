import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/teleprompter.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';
import 'package:g1_extended/services/lens_text_width.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/services/teleprompter_tracker.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/utils/glasses_text.dart';
import 'package:g1_extended/utils/lc3.dart';

/// How the script advances.
enum ScrollMode {
  voice('Voice', 'Follows what you say'),
  timed('Timed', 'Advances at a set pace'),
  manual('Manual', 'You advance it yourself, or tap a temple');

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

  static const String _nativeKey = 'teleprompter_native';

  /// The glasses' teleprompter draws narrower than the text command, so its
  /// lines are kept a little shorter than the lens width setting.
  static const double _nativeWidthRatio = 0.9;

  final BluetoothManager _bluetooth = BluetoothManager.singleton;
  final TextEditingController _script = TextEditingController();

  ScrollMode _mode = ScrollMode.voice;
  double _pace = 130;

  /// The glasses' own scrolling teleprompter, rather than text pages.
  bool _native = true;

  List<ScriptPage> _pages = const [];
  int _page = 0;

  List<ScriptLine> _lines = const [];
  GlassesTeleprompter? _glasses;
  bool _paused = false;

  TeleprompterTracker? _tracker;
  bool _running = false;
  String _heard = '';

  Timer? _timer;
  Timer? _drain;
  LiveTranscription? _session;
  StreamSubscription<String>? _transcript;

  @override
  void initState() {
    super.initState();
    _loadNative();
  }

  Future<void> _loadNative() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_nativeKey);
    if (stored != null && mounted) setState(() => _native = stored);
  }

  Future<void> _setNative(bool value) async {
    setState(() => _native = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nativeKey, value);
  }

  @override
  void dispose() {
    _glasses?.stop();
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
    if (_script.text.trim().isEmpty) {
      _notify('Nothing to read');
      return;
    }

    if (_native) {
      await _startNative();
    } else {
      await _startPages();
    }
  }

  Future<void> _startPages() async {
    final pages = ScriptPaginator.paginate(_script.text);
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

  Future<void> _startNative() async {
    final script = _script.text;
    if (!GlassesText.canDisplay(script)) {
      _notify(
          'The glasses cannot draw ${GlassesText.unsupportedScripts(script).join(', ')}');
      return;
    }

    final width = (LensTextWidth.current * _nativeWidthRatio).floor();
    final lines = ScriptLines.wrap(script, width: width);
    if (lines.isEmpty) {
      _notify('Nothing to read');
      return;
    }

    final glasses = GlassesTeleprompter()..onEnded = _onGlassesEnded;
    final started = await glasses.start(
      [for (final line in lines) line.text],
      mode: switch (_mode) {
        ScrollMode.timed => TeleprompterMode.timed,
        ScrollMode.manual => TeleprompterMode.manual,
        // The official app opens the glasses microphone in this mode only.
        ScrollMode.voice => TeleprompterMode.voiceFollow,
      },
    );
    if (!started) {
      _notify('The glasses did not open their teleprompter. '
          'Turn off "Glasses teleprompter" to use text pages.');
      return;
    }

    setState(() {
      _lines = lines;
      _glasses = glasses;
      _tracker = TeleprompterTracker(script);
      _heard = '';
      _paused = false;
      _running = true;
    });

    switch (_mode) {
      case ScrollMode.voice:
        await _startListening();
      case ScrollMode.timed:
        _scheduleNextLine();
      case ScrollMode.manual:
        break;
    }
  }

  void _onGlassesEnded(String reason) {
    _teardown();
    _glasses = null;
    if (mounted) setState(() => _running = false);
    _notify(reason);
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

    _drain = Timer.periodic(_drainInterval, (_) async {
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

    final glasses = _glasses;
    if (glasses != null) {
      // One line of what was just read stays above the reader's place.
      final line = ScriptLines.lineOf(_lines, tracker.position);
      final top = (line - 1).clamp(0, _lines.length - 1);
      if (top > glasses.top.value) await glasses.show(top);
      return;
    }

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

    final wordCount = _pages[_page].endWord - _pages[_page].firstWord;
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

  /// Moves the glasses' teleprompter one line once the top line has had the
  /// time its words take at the chosen pace.
  void _scheduleNextLine() {
    _timer?.cancel();
    final glasses = _glasses;
    if (glasses == null || _paused) return;

    final top = glasses.top.value;
    if (top + TeleprompterProtocol.visibleLines >= _lines.length) return;

    final words = _lines[top].endWord - _lines[top].firstWord;
    final seconds = words.clamp(1, 1000) / (_pace / 60);
    _timer = Timer(
      Duration(milliseconds: (seconds * 1000).round().clamp(800, 60000)),
      () async {
        if (!_running || _paused) return;
        await glasses.nextLine();
        _scheduleNextLine();
      },
    );
  }

  Future<void> _togglePause() async {
    final glasses = _glasses;
    if (glasses == null) return;
    final paused = !_paused;
    setState(() => _paused = paused);
    if (paused) {
      _timer?.cancel();
    } else {
      _scheduleNextLine();
    }
    await glasses.pause(paused);
  }

  // ----------------------------------------------------------------- common

  Future<void> _show(int page) async {
    if (page < 0 || page >= _pages.length) return;
    if (mounted) setState(() => _page = page);
    await _bluetooth.sendPriorityText(_pages[page].text);
  }

  Future<void> _step(int delta) async {
    final glasses = _glasses;
    if (glasses != null) {
      if (delta > 0) {
        await glasses.nextPage();
      } else {
        await glasses.previousPage();
      }
      // Moving by hand also moves the reader's place, or voice mode would
      // drag them straight back to where they were.
      final top = glasses.top.value;
      if (top < _lines.length) _tracker?.seek(_lines[top].firstWord);
      if (_mode == ScrollMode.timed) _scheduleNextLine();
      return;
    }

    final next = (_page + delta).clamp(0, _pages.length - 1);
    if (next == _page) return;

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
    final glasses = _glasses;
    _glasses = null;
    if (mounted) setState(() => _running = false);
    if (glasses != null) {
      await glasses.stop();
    } else {
      await _bluetooth.clearGlassesDisplay();
    }
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    _timer = null;
    _drain?.cancel();
    _drain = null;

    await _transcript?.cancel();
    _transcript = null;

    final session = _session;
    _session = null;
    if (session != null) {
      await session.close();
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
        child: !_running
            ? _buildEditor()
            : _glasses != null
                ? _buildRunningNative(_glasses!)
                : _buildRunning(),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Glasses teleprompter'),
          subtitle: const Text(
              'Scrolls on the lens with its own progress bar. Off: text pages'),
          value: _native,
          onChanged: _setNative,
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Widget _buildHeard() {
    if (_mode != ScrollMode.voice || _heard.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
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
    );
  }

  Widget _buildControls({Widget? middle}) {
    return Row(
      children: [
        Expanded(
          child: IconButton.filled(
            onPressed: () => _step(-1),
            icon: const Icon(Icons.skip_previous),
          ),
        ),
        const SizedBox(width: 12),
        if (middle != null) ...[
          Expanded(child: middle),
          const SizedBox(width: 12),
        ],
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
    );
  }

  Widget _buildRunningNative(GlassesTeleprompter glasses) {
    return ValueListenableBuilder<int>(
      valueListenable: glasses.top,
      builder: (context, top, _) {
        final shown = _lines
            .skip(top)
            .take(TeleprompterProtocol.visibleLines)
            .map((line) => line.text)
            .join('\n');
        final progress = TeleprompterProtocol.progress(
          top,
          _lines.length,
          voiceFollow: _mode == ScrollMode.voice,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Line ${top + 1} of ${_lines.length}  ·  ${_mode.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: AppColors.tile,
              color: AppColors.ink,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  shown,
                  style: const TextStyle(fontSize: 20, height: 1.5),
                ),
              ),
            ),
            _buildHeard(),
            _buildControls(
              middle: _mode == ScrollMode.timed
                  ? IconButton.filled(
                      onPressed: _togglePause,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                    )
                  : null,
            ),
          ],
        );
      },
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
        _buildHeard(),
        _buildControls(),
      ],
    );
  }
}
