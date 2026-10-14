import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/navigation.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';

/// Drives the glasses' own navigation screen the way the official app does:
/// open it, send each instruction to the left temple then the right, keep it
/// alive with a heartbeat a second to the right temple, close it at the end.
///
/// Every exchange goes through one queue. Replies are matched by command
/// byte, and a second request for 0x0A while one is waiting would cancel the
/// first — a heartbeat landing during an instruction would make that
/// instruction look refused.
class NativeNavigation {
  NativeNavigation({TeleprompterLink? link})
      : _link = link ?? BluetoothTeleprompterLink();

  static final NativeNavigation singleton = NativeNavigation();

  /// The same left-then-right exchange the teleprompter uses.
  final TeleprompterLink _link;

  static const Duration timeout = Duration(seconds: 2);
  static const Duration exitTimeout = Duration(seconds: 3);
  static const Duration beatEvery = Duration(seconds: 1);
  static const Duration retryPause = Duration(milliseconds: 20);

  int _seq = 0;
  int _beat = 0;
  bool _open = false;
  bool _busy = false;
  Timer? _heartbeat;
  Future<void> _queue = Future.value();

  /// True while the navigation screen is open on the glasses.
  bool get isOpen => _open;

  /// Shows [route], opening the screen first if needed. False when the
  /// glasses would not take it, so the caller can fall back to plain text.
  Future<bool> show(NavigationRoute route, {String speed = ''}) =>
      _serial(() async {
        if (!_link.isConnected) return false;
        if (!_open) {
          // retryCount 3, as the official navigateStart.
          if (!await _both(NavigationProtocol.start(seq: _next()), 4, timeout)) {
            return false;
          }
          _open = true;
          _heartbeat = Timer.periodic(beatEvery, (_) => _beatOnce());
        }
        final frame = NavigationProtocol.route(
          seq: _next(),
          icon: route.icon,
          roadName: route.road,
          nextDirectionDistance: route.distance,
          speed: speed,
        );
        return _both(frame, 4, timeout);
      });

  /// Tells the glasses the destination is reached.
  Future<void> arrive(String text) => _serial(() async {
        if (!_open || !_link.isConnected) return;
        // retryCount 5, as the official navigateArrive.
        await _both(NavigationProtocol.arrive(seq: _next(), text: text), 6,
            timeout);
      });

  /// Closes the navigation screen.
  Future<void> close() {
    _heartbeat?.cancel();
    _heartbeat = null;
    return _serial(() async {
      if (!_open) return;
      _open = false;
      if (!_link.isConnected) return;
      // retryCount 5, 3 s, as the official navigateExit.
      await _both(NavigationProtocol.exit(seq: _next()), 6, exitTimeout);
    });
  }

  void _beatOnce() {
    // A beat that would queue behind a slow exchange is not worth keeping.
    if (_busy || !_open) return;
    unawaited(_serial(() async {
      if (!_open || !_link.isConnected) return;
      final frame = NavigationProtocol.heartbeat(seq: _next(), beat: _beat++);
      await _link.exchange(
        GlassSide.right,
        frame,
        accept: (reply) => NavigationProtocol.accepts(reply, frame),
        timeout: timeout,
      );
    }));
  }

  int _next() => _seq = (_seq + 1) % 255;

  /// L then R; the whole exchange again on failure, [attempts] times.
  Future<bool> _both(Uint8List frame, int attempts, Duration wait) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await _side(GlassSide.left, frame, wait) &&
          await _side(GlassSide.right, frame, wait)) {
        return true;
      }
      await Future.delayed(retryPause);
    }
    debugPrint('NativeNavigation: 0x0A sub ${frame[4]} refused');
    return false;
  }

  Future<bool> _side(GlassSide side, Uint8List frame, Duration wait) async {
    final reply = await _link.exchange(
      side,
      frame,
      accept: (reply) => NavigationProtocol.accepts(reply, frame),
      timeout: wait,
    );
    return reply != null && NavigationProtocol.accepts(reply, frame);
  }

  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _queue.then((_) async {
      _busy = true;
      try {
        return await job();
      } finally {
        _busy = false;
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
