import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/teleprompter.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';
import 'package:g1_extended/services/glasses_event_log.dart';

/// What a teleprompter session needs from the radio: write to one temple and
/// wait for the answer that [accept] recognises.
abstract interface class TeleprompterLink {
  bool get isConnected;

  /// Returns the answer, or null when the write failed or nothing came back
  /// within [timeout].
  Future<List<int>?> exchange(
    GlassSide side,
    Uint8List frame, {
    required bool Function(List<int> reply) accept,
    required Duration timeout,
  });
}

class BluetoothTeleprompterLink implements TeleprompterLink {
  BluetoothTeleprompterLink({
    BluetoothManager? bluetooth,
    BluetoothReciever? receiver,
  })  : _bluetooth = bluetooth ?? BluetoothManager.singleton,
        _receiver = receiver ?? BluetoothReciever();

  final BluetoothManager _bluetooth;
  final BluetoothReciever _receiver;

  @override
  bool get isConnected => _bluetooth.isConnected;

  @override
  Future<List<int>?> exchange(
    GlassSide side,
    Uint8List frame, {
    required bool Function(List<int> reply) accept,
    required Duration timeout,
  }) async {
    final glass =
        side == GlassSide.left ? _bluetooth.leftGlass : _bluetooth.rightGlass;
    if (glass == null) return null;

    // Listening starts before the write, or a quick answer would be missed.
    final reply = _receiver.awaitReply(
      frame[0],
      timeout: timeout,
      accept: accept,
      side: side,
    );
    if (!await glass.sendData(frame)) return null;
    return reply;
  }
}

/// Runs the glasses' own teleprompter, which scrolls a script on the lens
/// instead of redrawing it page by page through the text command.
///
/// Mirrors what the official app does: every frame goes to the left temple,
/// then to the right one only if the left took it; a heartbeat goes to the
/// right temple every two seconds; screens that are overtaken before they
/// are sent are dropped rather than queued.
class GlassesTeleprompter {
  GlassesTeleprompter({
    TeleprompterLink? link,
    Stream<GlassesEvent>? taps,
  })  : _link = link ?? BluetoothTeleprompterLink(),
        _taps = taps ??
            GlassesEventLog.instance.changes
                .where((events) => events.isNotEmpty)
                .map((events) => events.first);

  /// The session on the glasses right now, if any. The receiver leaves the
  /// touchpad to it while it runs.
  static GlassesTeleprompter? active;

  static bool get isActive => active != null;

  static const Duration heartbeatInterval = Duration(seconds: 2);

  /// The official app gives up after this many unanswered heartbeats.
  static const int heartbeatsLostBeforeGivingUp = 10;

  // The official app waits 3 s for a start packet, 0.5 s (left) and 1 s
  // (right) for a screen, and 2 s for a heartbeat. The left gets a little
  // more here: this app writes with response, which takes longer.
  static const Duration _startTimeout = Duration(seconds: 3);
  static const Duration _leftTimeout = Duration(seconds: 1);
  static const Duration _rightTimeout = Duration(seconds: 1);
  static const Duration _heartbeatTimeout = Duration(seconds: 2);

  /// The official app only reports a pause once this much has run.
  static const Duration _minimumBeforePause = Duration(seconds: 3);

  final TeleprompterLink _link;
  final Stream<GlassesEvent> _taps;

  List<String> _lines = const [];
  int _seq = 0;
  int _top = 0;
  bool _running = false;
  bool _scrollAnimates = true;

  Timer? _heartbeat;
  bool _heartbeatInFlight = false;
  int _heartbeatsLost = 0;
  StreamSubscription<GlassesEvent>? _tapSubscription;

  final Stopwatch _clock = Stopwatch();

  bool _sending = false;
  int? _pendingTop;

  /// Called once when the session ends without being asked to: the glasses
  /// were double-tapped out of it, or stopped answering.
  void Function(String reason)? onEnded;

  /// The first line on the lens.
  final ValueNotifier<int> top = ValueNotifier<int>(0);

  bool get isRunning => _running;
  int get lineCount => _lines.length;

  /// Puts the first screen up. Returns false when the glasses refused it.
  Future<bool> start(
    List<String> lines, {
    TeleprompterMode mode = TeleprompterMode.manual,
    int countdownSeconds = 0,
  }) async {
    if (_running || lines.isEmpty || !_link.isConnected) return false;
    await active?.stop();

    _lines = List.unmodifiable(lines);
    _top = 0;
    top.value = 0;
    _scrollAnimates = true;

    final packets = TeleprompterProtocol.screenPackets(_lines, 0);
    final progress = TeleprompterProtocol.progress(0, _lines.length);
    for (var i = 0; i < packets.length; i++) {
      final frame = TeleprompterProtocol.start(
        seq: _seq++,
        packetCount: packets.length,
        packetIndex: i + 1,
        mode: mode,
        progress: progress,
        text: packets[i],
        countdownSeconds: countdownSeconds,
      );
      final ok = await _toBoth(
        frame,
        TeleprompterProtocol.subStart,
        leftTimeout: _startTimeout,
        rightTimeout: _startTimeout,
      );
      if (!ok) {
        debugPrint('GlassesTeleprompter: start packet ${i + 1} refused');
        return false;
      }
    }

    _running = true;
    active = this;
    _clock
      ..reset()
      ..start();
    _heartbeatsLost = 0;
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _beat());
    _tapSubscription = _taps.listen(_onTap);
    return true;
  }

  /// Shows the screen whose first line is [line]. Requests made while a
  /// screen is being sent replace each other; only the last one is sent.
  Future<void> show(int line) async {
    if (!_running || _lines.isEmpty) return;
    final target = line.clamp(0, _lines.length - 1);
    if (target == _top && _pendingTop == null) return;

    _pendingTop = target;
    if (_sending) return;

    _sending = true;
    try {
      while (_running && _pendingTop != null) {
        final next = _pendingTop!;
        _pendingTop = null;
        if (next == _top) continue;
        if (await _sendScreen(next, scrolled: next == _top + 1)) {
          _top = next;
          top.value = next;
        }
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> nextLine() => show(_top + 1);

  Future<void> nextPage() => show(_top + TeleprompterProtocol.visibleLines);

  Future<void> previousPage() => show(_top - TeleprompterProtocol.visibleLines);

  /// Tells the glasses the timed scroll stopped or resumed.
  Future<bool> pause(bool paused) async {
    if (!_running || _clock.elapsed < _minimumBeforePause) return false;
    if (paused) {
      _clock.stop();
    } else {
      _clock.start();
    }
    final frame = TeleprompterProtocol.pause(
      seq: _seq++,
      paused: paused,
      elapsedSeconds: _clock.elapsed.inSeconds,
    );
    return _sendToBoth(frame, TeleprompterProtocol.answersPause);
  }

  /// Takes the teleprompter off the lens.
  Future<void> stop() async {
    if (!_running) return;
    _end();
    await _sendToBoth(
      TeleprompterProtocol.stop(_seq++),
      (reply) =>
          TeleprompterProtocol.answers(reply, TeleprompterProtocol.subStop),
    );
  }

  void _end() {
    _running = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _tapSubscription?.cancel();
    _tapSubscription = null;
    _clock.stop();
    _pendingTop = null;
    if (identical(active, this)) active = null;
  }

  Future<bool> _sendScreen(int line, {required bool scrolled}) async {
    final animate = scrolled && _scrollAnimates;
    final packets = TeleprompterProtocol.screenPackets(_lines, line);
    final progress = TeleprompterProtocol.progress(line, _lines.length);

    for (var i = 0; i < packets.length; i++) {
      Uint8List frame(bool animated) => TeleprompterProtocol.screen(
            seq: _seq++,
            packetCount: packets.length,
            packetIndex: i + 1,
            progress: progress,
            text: packets[i],
            scrolled: animated,
          );

      var ok = await _toBoth(frame(animate), TeleprompterProtocol.subScreen);
      if (!ok && animate) {
        // Firmware older than 1.2.10 has no scroll animation: stop asking.
        _scrollAnimates = false;
        ok = await _toBoth(frame(false), TeleprompterProtocol.subScreen);
      }
      if (!ok) return false;
    }
    return true;
  }

  /// Left first, then right only if the left took it.
  Future<bool> _toBoth(
    Uint8List frame,
    int sub, {
    Duration leftTimeout = _leftTimeout,
    Duration rightTimeout = _rightTimeout,
  }) async {
    bool answers(List<int> reply) => TeleprompterProtocol.answers(reply, sub);

    final left = await _link.exchange(GlassSide.left, frame,
        accept: answers, timeout: leftTimeout);
    if (left == null || !TeleprompterProtocol.accepted(left)) return false;

    final right = await _link.exchange(GlassSide.right, frame,
        accept: answers, timeout: rightTimeout);
    return right != null && TeleprompterProtocol.accepted(right);
  }

  Future<bool> _sendToBoth(
    Uint8List frame,
    bool Function(List<int> reply) accept,
  ) async {
    final left = await _link.exchange(GlassSide.left, frame,
        accept: accept, timeout: _leftTimeout);
    if (left == null) return false;
    final right = await _link.exchange(GlassSide.right, frame,
        accept: accept, timeout: _rightTimeout);
    return right != null;
  }

  Future<void> _beat() async {
    if (!_running || _heartbeatInFlight) return;
    _heartbeatInFlight = true;
    try {
      final reply = await _link.exchange(
        GlassSide.right,
        TeleprompterProtocol.heartbeat(_seq++),
        accept: TeleprompterProtocol.answersHeartbeat,
        timeout: _heartbeatTimeout,
      );
      if (reply != null) {
        _heartbeatsLost = 0;
        return;
      }
      if (++_heartbeatsLost >= heartbeatsLostBeforeGivingUp && _running) {
        _end();
        onEnded?.call('The glasses stopped answering');
      }
    } finally {
      _heartbeatInFlight = false;
    }
  }

  void _onTap(GlassesEvent event) {
    if (!_running) return;
    switch (event.subcommand) {
      case 0x00:
        // A double tap leaves the teleprompter on the glasses themselves.
        _end();
        onEnded?.call('Closed on the glasses');
      case 0x01:
        if (event.side == GlassSide.left.name) {
          previousPage();
        } else {
          nextPage();
        }
    }
  }
}
