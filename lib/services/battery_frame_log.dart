import 'dart:collection';

import 'package:g1_extended/models/g1/glass.dart';

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

  bool enabled = false;

  UnmodifiableListView<BatteryFrame> get frames =>
      UnmodifiableListView(_frames.toList().reversed.toList());

  void record(GlassSide side, List<int> bytes) {
    if (!enabled) return;

    _frames.addLast(BatteryFrame(
      side: side,
      bytes: List<int>.unmodifiable(bytes),
      at: DateTime.now(),
      note: currentNote,
    ));
    while (_frames.length > _capacity) {
      _frames.removeFirst();
    }
  }

  void clear() => _frames.clear();

  /// One frame per line, ready to paste into an issue.
  String export() {
    if (_frames.isEmpty) return 'No frames captured.';
    return _frames.map((f) => f.toString()).join('\n');
  }

  /// Byte positions that differ across the captured frames, per side.
  ///
  /// A byte that never changes cannot be the case battery. This narrows the
  /// search to the handful that actually move.
  Map<String, List<int>> varyingPositions() {
    final result = <String, List<int>>{};

    for (final side in GlassSide.values) {
      final forSide =
          _frames.where((f) => f.side == side).map((f) => f.bytes).toList();
      if (forSide.length < 2) continue;

      final length =
          forSide.map((b) => b.length).reduce((a, b) => a < b ? a : b);
      final varying = <int>[];

      for (var i = 0; i < length; i++) {
        final first = forSide.first[i];
        if (forSide.any((bytes) => bytes[i] != first)) varying.add(i);
      }
      result[side == GlassSide.left ? 'L' : 'R'] = varying;
    }
    return result;
  }
}
