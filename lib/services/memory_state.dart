import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the system will let this process have, right now.
///
/// The offline speech model's loader is native: it allocates outside Dart's
/// heap and, when there is not enough, Android ends the process from the
/// outside. Nothing throws, nothing is logged, the app simply disappears —
/// which is what pressing Start on the captions screen did. There is no
/// catching that after the fact, so the only remedy is to ask beforehand
/// and say so plainly instead of vanishing.
class MemoryState {
  const MemoryState({
    required this.availableBytes,
    required this.totalBytes,
    required this.lowMemoryThresholdBytes,
    required this.systemLowMemory,
    required this.heapLimitMb,
  });

  final int availableBytes;
  final int totalBytes;
  final int lowMemoryThresholdBytes;
  final bool systemLowMemory;

  /// The ceiling this process may reach, in megabytes.
  final int heapLimitMb;

  /// Roughly what the English model costs once the native side has it
  /// open: the two graph files are 23 and 21 MB on disk and are expanded
  /// in memory, and the loader needs room to build them as well.
  static const int speechModelCostMb = 200;

  /// Whether loading the speech model is likely to end the process.
  ///
  /// Deliberately cautious. A false alarm costs a dialog the wearer can
  /// dismiss; being wrong the other way costs the whole app, mid-sentence,
  /// with the glasses dropping their link as it goes.
  bool get speechModelIsRisky {
    if (systemLowMemory) return true;
    final availableMb = availableBytes ~/ (1024 * 1024);
    return availableMb < speechModelCostMb || heapLimitMb < 256;
  }

  String get summary =>
      '${availableBytes ~/ (1024 * 1024)} MB free of '
      '${totalBytes ~/ (1024 * 1024)} MB, heap ceiling $heapLimitMb MB';

  static const MethodChannel _channel =
      MethodChannel('fr.simonlabbe.g1extended/memory');

  /// Null when the platform does not answer — on which nothing should be
  /// blocked, since an unknown is not a warning.
  static Future<MemoryState?> read() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('state');
      if (raw == null) return null;
      return MemoryState(
        availableBytes: (raw['availableBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
        lowMemoryThresholdBytes:
            (raw['lowMemoryThresholdBytes'] as num?)?.toInt() ?? 0,
        systemLowMemory: raw['systemLowMemory'] as bool? ?? false,
        heapLimitMb: (raw['heapLimitMb'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('MemoryState: unavailable: $e');
      return null;
    }
  }
}
