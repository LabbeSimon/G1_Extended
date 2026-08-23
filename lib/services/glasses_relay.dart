import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Carries glasses-bound bytes from an isolate that has no link to the one
/// that does.
///
/// The interface's BluetoothManager drives screens; the background
/// service's holds the glasses. Before this, a command issued from a
/// screen while the interface held no link of its own returned false and
/// vanished — a brightness change or a silent-mode toggle that just did
/// nothing, with nothing to say why.
abstract final class GlassesRelay {
  static const String event = 'relayToGlasses';

  /// Hands [bytes] to the owning isolate. Fire and forget by design: the
  /// service bus has no replies, and the owner already retries and logs.
  static void send(List<int> bytes, {String side = 'both'}) {
    try {
      FlutterBackgroundService().invoke(event, {
        'side': side,
        'bytes': bytes,
      });
      debugPrint('GlassesRelay: ${bytes.length} byte(s) relayed to $side');
    } catch (e) {
      debugPrint('GlassesRelay: could not relay: $e');
    }
  }

  /// Asks the owner to scan and pair, and does not take silence for an
  /// answer.
  ///
  /// The service starts asynchronously; an event invoked before its
  /// listeners are registered is lost without a trace. So the ask repeats
  /// until the service says anything back on 'pairingUpdate' — its first
  /// message doubles as the handshake — and gives up loudly after ten
  /// seconds rather than leaving a button that did nothing.
  static Future<bool> pairWithHandshake({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final service = FlutterBackgroundService();
    final acked = Completer<bool>();

    late StreamSubscription<Map<String, dynamic>?> sub;
    sub = service.on('pairingUpdate').listen((_) {
      if (!acked.isCompleted) acked.complete(true);
    });

    final deadline = DateTime.now().add(timeout);
    try {
      while (!acked.isCompleted && DateTime.now().isBefore(deadline)) {
        try {
          service.invoke('startPairing');
        } catch (e) {
          debugPrint('GlassesRelay: pairing invoke failed: $e');
        }
        await Future.any([
          acked.future,
          Future.delayed(const Duration(milliseconds: 800)),
        ]);
      }
      return acked.isCompleted;
    } finally {
      await sub.cancel();
    }
  }

  /// Asks the owner to reconnect from the stored pairing.
  static void reconnect() {
    try {
      FlutterBackgroundService().invoke('reconnectNow');
    } catch (e) {
      debugPrint('GlassesRelay: could not ask for a reconnect: $e');
    }
  }
}
