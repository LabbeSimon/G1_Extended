import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The processor architectures this phone can run, most preferred first.
///
/// Releases carry one build per architecture plus a universal one holding
/// them all. The universal build is nearly twice the size, and the excess
/// is native code for processors this phone does not have — so knowing the
/// architecture is what turns a ninety megabyte update into a forty-five
/// megabyte one. On a beta channel that is the difference between updating
/// readily and putting it off.
class DeviceAbis {
  const DeviceAbis._();

  static const MethodChannel _channel =
      MethodChannel('fr.simonlabbe.g1extended/memory');

  static List<String>? _cached;

  /// Never changes while the app runs, so it is asked once.
  static Future<List<String>> supported() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final abis = await _channel.invokeListMethod<String>('abis');
      // An empty answer is the same as no answer: fall back to the
      // universal build rather than guess an architecture wrong, which
      // would install and then fail to run.
      _cached = (abis == null || abis.isEmpty) ? const [] : abis;
    } catch (e) {
      debugPrint('DeviceAbis: unavailable: $e');
      _cached = const [];
    }

    return _cached!;
  }

  @visibleForTesting
  static void setForTest(List<String> abis) => _cached = abis;
}
