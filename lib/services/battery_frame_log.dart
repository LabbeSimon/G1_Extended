import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';

/// One raw battery reply, exactly as the glasses sent it.
class BatteryFrame {
  final GlassSide side;
  final List<int> bytes;
  final DateTime at;

  /// What the wearer was doing when it was captured, if they said.
  final String? note;

  const BatteryFrame({
    required this.side,
    required this.bytes,
    required this.at,
    this.note,
  });

  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  String toString() {
    final time = at.toIso8601String().substring(11, 19);
    final label = side == GlassSide.left ? 'L' : 'R';
    return '$time $label ${note == null ? '' : '[$note] '}$hex';
  }
}

/// Keeps the last battery replies so they can be read back and compared.
///
/// The protocol document describes this frame as
/// `2C 66 <percentage> <in case, arms closed, charging, voltage>`, but its
/// sample bytes do not line up with that description: the last three are the
/// firmware version, and the byte the app reads as a charging flag holds 0x5d
/// on an empty arm and 0x80 on a full one. Whatever is in there, it is not a
/// boolean.
///
/// So rather than guess at offsets, capture real frames in known states —
/// in the case, out of the case, plugged in, unplugged — and diff them. Two
/// labelled captures are worth more than any amount of reasoning about an
/// ambiguous table.
class BatteryFrameLog {
  BatteryFrameLog._internal();
  static final BatteryFrameLog singleton = BatteryFrameLog._internal();
  factory BatteryFrameLog() => singleton;

  static const int _capacity = 200;

  final Queue<BatteryFrame> _frames = Queue<BatteryFrame>();

  /// Set from the debug screen to tag whatever is captured next.
  String? currentNote;

  bool _enabled = false;
  Timer? _poller;

  /// The glasses only answer when asked. Left to the app's ordinary schedule
  /// a state would be sampled every couple of minutes, which makes holding a
  /// pose long enough to catch one an exercise in patience. While recording,
  /// they are asked continuously instead.
  static const Duration pollInterval = Duration(seconds: 2);

  final StreamController<int> _countController =
      StreamController<int>.broadcast();

  /// Emits the frame count as it grows, so a screen can show it live.
  Stream<int> get frameCount => _countController.stream;

  bool get enabled => _enabled;

  /// Starts or stops recording, and the polling that feeds it.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;

    _poller?.cancel();
    _poller = null;

    if (!value) return;

    // Ask once immediately: waiting two seconds for the first frame makes the
    // button feel broken.
    unawaited(_poll());
    _poller = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (!_enabled) return;
    try {
      await BluetoothManager.singleton.requestBatteryInfo();
    } catch (e) {
      debugPrint('BatteryFrameLog: could not request battery: $e');
    }
  }

  UnmodifiableListView<BatteryFrame> get frames =>
      UnmodifiableListView(_frames.toList().reversed.toList());

  void record(GlassSide side, List<int> bytes) {
    if (!_enabled) return;

    _frames.addLast(BatteryFrame(
      side: side,
      bytes: List<int>.unmodifiable(bytes),
      at: DateTime.now(),
      note: currentNote,
    ));
    while (_frames.length > _capacity) {
      _frames.removeFirst();
    }

    if (!_countController.isClosed) _countController.add(_frames.length);
  }

  void clear() {
    _frames.clear();
    if (!_countController.isClosed) _countController.add(0);
  }

  /// One frame per line, ready to paste into an issue.
  String export() {
    if (_frames.isEmpty) return 'No frames captured.';
    return _frames.map((f) => f.toString()).join('\n');
  }

  /// The distinct states captured so far.
  ///
  /// Comparing frames is only meaningful across states: a hundred frames of
  /// the same situation prove nothing, and two frames of two situations
  /// prove a great deal.
  List<String> capturedStates() {
    final states = _frames
        .map((f) => f.note)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return states;
  }

  /// Byte positions that change when the *state* changes, per side.
  ///
  /// A byte that holds still through every state cannot be the case battery,
  /// so this is what narrows the search. Bytes that move within a single
  /// state are noise — voltage and temperature drift constantly — and are
  /// excluded by comparing each state's first frame only.
  Map<String, List<int>> varyingPositions() {
    final result = <String, List<int>>{};

    for (final side in GlassSide.values) {
      final label = side == GlassSide.left ? 'L' : 'R';

      // One representative frame per state.
      final representatives = <String, List<int>>{};
      for (final frame in _frames) {
        if (frame.side != side) continue;
        final state = frame.note ?? '(untagged)';
        representatives.putIfAbsent(state, () => frame.bytes);
      }

      if (representatives.length < 2) {
        result[label] = const [];
        continue;
      }

      final samples = representatives.values.toList();
      final length =
          samples.map((b) => b.length).reduce((a, b) => a < b ? a : b);

      final varying = <int>[];
      for (var i = 0; i < length; i++) {
        final first = samples.first[i];
        if (samples.any((bytes) => bytes[i] != first)) varying.add(i);
      }
      result[label] = varying;
    }

    return result;
  }

  /// A byte-by-byte table across states, which is what actually gets read.
  ///
  /// Rows are states, columns are byte positions. Seeing them side by side is
  /// how a candidate for the case battery becomes obvious.
  Map<String, Map<String, List<int>>> comparisonTable() {
    final table = <String, Map<String, List<int>>>{};

    for (final side in GlassSide.values) {
      final label = side == GlassSide.left ? 'L' : 'R';
      final rows = <String, List<int>>{};

      for (final frame in _frames) {
        if (frame.side != side) continue;
        rows.putIfAbsent(frame.note ?? '(untagged)', () => frame.bytes);
      }
      if (rows.isNotEmpty) table[label] = rows;
    }

    return table;
  }
}
