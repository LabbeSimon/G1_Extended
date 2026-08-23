import 'package:shared_preferences/shared_preferences.dart';

/// The four touchpad gestures this app can answer.
enum TempleGesture {
  leftTap('gesture_left_tap'),
  leftHold('gesture_left_hold'),
  rightTap('gesture_right_tap'),
  rightHold('gesture_right_hold');

  const TempleGesture(this.storageKey);
  final String storageKey;
}

/// What a gesture does.
///
/// `firmware` means standing aside: the glasses already assign meanings to
/// every one of these gestures — Even AI on the left hold, their own
/// notification list on the left tap, quick note on the right hold — and
/// two handlers on one gesture is a fight the firmware usually wins. That
/// lesson cost a released bug, so it is the default anywhere the firmware
/// has a use for the gesture.
enum GestureAction {
  /// Leave the gesture to the glasses.
  firmware('firmware'),

  /// Hold to speak, release to finish; shown live on the lens.
  dictate('dictate'),

  /// Toggle a dictation that becomes a note in the library.
  dictateNote('dictate_note'),

  /// Show the most recent phone notification again; repeated use walks
  /// back through the history.
  recallNotification('recall'),

  /// Silence or wake the display.
  toggleSilent('silent'),

  /// Start or stop the speedometer.
  toggleSpeedometer('speedometer');

  const GestureAction(this.wire);

  /// The stored value. Renaming an enum constant must not reinterpret
  /// what people configured, so storage speaks these strings, not names.
  final String wire;

  static GestureAction fromWire(String? value, {required GestureAction fallback}) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return fallback;
  }
}

/// Which actions make sense on which gesture.
///
/// Holds are stateful — they begin something on press and end it on
/// release — so only the two dictation actions, which are built as
/// begin/end pairs, may sit on one. An instantaneous action on a hold
/// would fire on press and leave the release meaning nothing, which reads
/// as the gesture working half the time.
abstract final class TempleGestureRules {
  static const Map<TempleGesture, List<GestureAction>> allowed = {
    TempleGesture.leftTap: [
      GestureAction.firmware,
      GestureAction.recallNotification,
      GestureAction.toggleSilent,
      GestureAction.toggleSpeedometer,
    ],
    TempleGesture.rightTap: [
      GestureAction.firmware,
      GestureAction.recallNotification,
      GestureAction.toggleSilent,
      GestureAction.toggleSpeedometer,
    ],
    TempleGesture.leftHold: [
      GestureAction.firmware,
      GestureAction.dictate,
      GestureAction.dictateNote,
    ],
    TempleGesture.rightHold: [
      GestureAction.firmware,
      GestureAction.dictate,
      GestureAction.dictateNote,
    ],
  };

  /// What each gesture does out of the box — the behaviour the app has
  /// shipped with, so updating changes nothing until someone chooses.
  static const Map<TempleGesture, GestureAction> defaults = {
    TempleGesture.leftTap: GestureAction.firmware,
    TempleGesture.leftHold: GestureAction.dictate,
    TempleGesture.rightTap: GestureAction.firmware,
    TempleGesture.rightHold: GestureAction.dictateNote,
  };

  /// What the glasses themselves do with the gesture, for the settings
  /// screen to say — choosing to override is informed or it is a trap.
  static const Map<TempleGesture, String> firmwareMeaning = {
    TempleGesture.leftTap:
        'On the dashboard, opens the glasses\' own notification list; '
        'inside it, moves to the next one.',
    TempleGesture.leftHold: 'Starts Even AI.',
    TempleGesture.rightTap: 'On the dashboard, turns the page.',
    TempleGesture.rightHold: 'Starts the glasses\' own quick note recorder.',
  };
}

/// Reads and writes the configuration.
///
/// Settings are written by the interface isolate and read by whichever
/// isolate holds the glasses, so reads go through reload() — a
/// SharedPreferences instance caches per isolate, and without the reload
/// the receiving isolate would keep answering from the values it saw at
/// startup. Gestures are rare; the reload is cheap where it matters.
class TempleGestureConfig {
  TempleGestureConfig._internal();
  static final TempleGestureConfig singleton = TempleGestureConfig._internal();
  factory TempleGestureConfig() => singleton;

  /// The pre-gesture setting this replaces.
  static const String _legacyRecallKey = 'recall_on_left_tap';

  Future<GestureAction> actionFor(TempleGesture gesture) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final stored = prefs.getString(gesture.storageKey);
    if (stored != null) {
      final action = GestureAction.fromWire(
        stored,
        fallback: TempleGestureRules.defaults[gesture]!,
      );
      // A stored value from a future version may name an action this
      // gesture cannot carry; the default is safer than a half-working one.
      return TempleGestureRules.allowed[gesture]!.contains(action)
          ? action
          : TempleGestureRules.defaults[gesture]!;
    }

    // The old boolean, honoured so an update changes nobody's glasses.
    if (gesture == TempleGesture.leftTap &&
        (prefs.getBool(_legacyRecallKey) ?? false)) {
      return GestureAction.recallNotification;
    }

    return TempleGestureRules.defaults[gesture]!;
  }

  Future<void> setAction(TempleGesture gesture, GestureAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(gesture.storageKey, action.wire);
    // The boolean it replaces must not linger and contradict it.
    if (gesture == TempleGesture.leftTap) {
      await prefs.remove(_legacyRecallKey);
    }
  }
}
