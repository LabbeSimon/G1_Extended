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

  /// Asks the owner to scan for and pair new glasses.
  ///
  /// Pairing is radio work, and radio work happens in exactly one isolate.
  /// Progress comes back as 'pairingUpdate' events and state broadcasts.
  static void pair() {
    try {
      FlutterBackgroundService().invoke('startPairing');
    } catch (e) {
      debugPrint('GlassesRelay: could not ask for pairing: $e');
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
