import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/text.dart';

/// How wide a line of text is allowed to be, kept where it can be changed
/// without a rebuild.
///
/// The number is disputed — twenty was inherited from the fork, twenty-five
/// is what the teleprompter's paginator says was measured on hardware, forty
/// is what two other implementations compute from the pixel column. Settling
/// it needs glasses, and whoever settles it should be able to keep the
/// answer without waiting for a release.
///
/// The cached value exists because text is sent from paths that cannot
/// await: it is read once and kept, so a change applies to the next message
/// rather than to the one in flight.
abstract final class LensTextWidth {
  static const String _key = 'lens_chars_per_line';

  /// The widths worth trying, in the order the Debug screen offers them.
  static const List<int> candidates = [20, 25, TextMessage.charsPerLine];

  static int _cached = TextMessage.charsPerLine;

  /// What the sender should use right now.
  static int get current => _cached;

  /// Reads the stored width into the cache. Call once at startup.
  static Future<int> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    _cached = _sane(stored) ? stored! : TextMessage.charsPerLine;
    return _cached;
  }

  static Future<void> set(int width) async {
    if (!_sane(width)) {
      throw ArgumentError.value(width, 'width', 'not a plausible line width');
    }
    _cached = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, width);
  }

  /// Back to whatever the code ships with.
  static Future<void> reset() async {
    _cached = TextMessage.charsPerLine;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// A width outside this range is a bug or a corrupted preference, not a
  /// choice: ten characters would paginate a sentence into a book, and a
  /// hundred would run off a panel that holds about forty.
  static bool _sane(int? width) => width != null && width >= 10 && width <= 80;
}
