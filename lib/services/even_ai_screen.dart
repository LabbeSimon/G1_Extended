import 'dart:async';
import 'dart:typed_data';

import 'package:g1_extended/models/g1/even_ai.dart';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';

/// Closes the glasses' AI screen the way the official app does.
///
/// Holding the left temple opens it; the answer is drawn into it; and it
/// stays open, scroll bar and all, until something ends the session. The
/// official app sends status 0 to the left temple, then to the right one if
/// the left took it, up to three times 100 ms apart.
class EvenAiScreen {
  EvenAiScreen({TeleprompterLink? link})
      : _link = link ?? BluetoothTeleprompterLink();

  static final EvenAiScreen singleton = EvenAiScreen();

  /// The same left-then-right exchange the teleprompter uses: nothing in it
  /// is specific to the teleprompter.
  final TeleprompterLink _link;
  int _seq = 0;

  static const Duration timeout = Duration(seconds: 2);
  static const int attempts = 3;
  static const Duration retryPause = Duration(milliseconds: 100);

  /// True when both temples took the frame.
  Future<bool> close() async {
    if (!_link.isConnected) return false;

    final frame = EvenAiProtocol.exit(seq: _seq++);
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await _accepted(GlassSide.left, frame) &&
          await _accepted(GlassSide.right, frame)) {
        return true;
      }
      await Future.delayed(retryPause);
    }
    return false;
  }

  Future<bool> _accepted(GlassSide side, Uint8List frame) async {
    final reply = await _link.exchange(
      side,
      frame,
      accept: EvenAiProtocol.acceptsStatus,
      timeout: timeout,
    );
    return reply != null && EvenAiProtocol.acceptsStatus(reply);
  }
}
