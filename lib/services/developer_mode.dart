import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// The hidden switch that reveals the diagnostic tools.
///
/// Tapping the version ten times is the convention Android itself uses, and
/// it is the right shape here: someone who wants to read protocol frames will
/// find it, and someone who just wants their glasses to work will never meet
/// a screen full of hex.
class DeveloperMode {
  DeveloperMode._internal();
  static final DeveloperMode singleton = DeveloperMode._internal();
  factory DeveloperMode() => singleton;

  static const int tapsRequired = 10;

  /// Taps further apart than this start the count again, so stray presses
  /// never accumulate into an accidental unlock.
  static const Duration tapWindow = Duration(seconds: 2);

  static const String _key = 'developer_mode';

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  int _taps = 0;
  DateTime? _lastTap;

  /// Emits whenever developer mode is turned on or off.
  Stream<bool> get changes => _controller.stream;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    _taps = 0;
    _lastTap = null;
    if (!_controller.isClosed) _controller.add(enabled);
  }

  /// Records one tap on the version and reports what to tell the user.
  Future<TapOutcome> registerTap() async {
    if (await isEnabled()) return const TapOutcome.alreadyOn();

    final now = DateTime.now();
    if (_lastTap == null || now.difference(_lastTap!) > tapWindow) {
      _taps = 0;
    }
    _lastTap = now;
    _taps++;

    if (_taps >= tapsRequired) {
      await setEnabled(true);
      return const TapOutcome.unlocked();
    }

    final remaining = tapsRequired - _taps;
    // Staying quiet for the first few taps is what keeps it hidden.
    return TapOutcome.progress(remaining, announce: remaining <= 4);
  }
}

/// What the caller should say, if anything, after a tap.
class TapOutcome {
  final bool unlocked;
  final bool alreadyEnabled;
  final int remaining;
  final bool announce;

  const TapOutcome.unlocked()
      : unlocked = true,
        alreadyEnabled = false,
        remaining = 0,
        announce = true;

  const TapOutcome.alreadyOn()
      : unlocked = false,
        alreadyEnabled = true,
        remaining = 0,
        announce = false;

  const TapOutcome.progress(this.remaining, {required this.announce})
      : unlocked = false,
        alreadyEnabled = false;

  String? get message {
    if (unlocked) return 'Developer options are on';
    if (!announce || remaining <= 0) return null;
    return remaining == 1
        ? '1 step from developer options'
        : '$remaining steps from developer options';
  }
}
