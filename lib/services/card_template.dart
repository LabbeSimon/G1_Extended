import 'package:intl/intl.dart';

/// A value a template can put on the glasses.
class CardToken {
  final String name;
  final String description;
  final String Function() resolve;

  const CardToken(this.name, this.description, this.resolve);
}

/// Fills a user-written line with live values.
///
/// The glasses can only show four notes, and the firmware decides how they
/// look. What it does not decide is what they say — so this is where "display
/// my own information" actually lives.
///
/// Anything the app already knows can be dropped into a line with braces:
/// `{time}`, `{battery}`, `{temp}`. An unknown token is left exactly as
/// written rather than silently deleted, so a typo is visible on the lens
/// instead of leaving a mysterious gap.
abstract final class CardTemplate {
  /// Matches `{name}`, and nothing that merely looks like it.
  static final RegExp _token = RegExp(r'\{([a-z_][a-z0-9_]*)\}');

  /// Fills [template] from [values]. Tokens with no value are left alone.
  static String render(String template, Map<String, String?> values) {
    return template.replaceAllMapped(_token, (match) {
      final name = match.group(1)!;
      if (!values.containsKey(name)) return match.group(0)!;

      final value = values[name];
      // A known token with nothing behind it yet reads better as a dash than
      // as a blank the user cannot tell from a bug.
      return (value == null || value.isEmpty) ? '--' : value;
    });
  }

  /// The token names a template may use, for the help text on the editor.
  static const Map<String, String> known = {
    'time': 'Current time',
    'date': 'Current date',
    'day': 'Day of the week',
    'battery': 'Glasses battery, lowest side',
    'battery_left': 'Left temple battery',
    'battery_right': 'Right temple battery',
    'temp': 'Temperature',
    'weather': 'Weather description',
    'speed': 'Current speed',
    'next_event': 'Next calendar event',
    'value': 'Value fetched from the card\'s source',
    'hr': 'Heart rate, from a paired Bluetooth sensor',
  };

  /// Token names found in a template that nothing will ever fill.
  static List<String> unknownTokens(String template) {
    return _token
        .allMatches(template)
        .map((m) => m.group(1)!)
        .where((name) => !known.containsKey(name))
        .toSet()
        .toList();
  }

  /// Standard formats, so every card renders time the same way.
  static String formatTime(DateTime now, {required bool twentyFourHour}) =>
      DateFormat(twentyFourHour ? 'HH:mm' : 'h:mm a').format(now);

  static String formatDate(DateTime now) => DateFormat('d MMM').format(now);

  static String formatDay(DateTime now) => DateFormat('EEE').format(now);
}

/// Pulls a value out of a fetched document.
///
/// A card can point at a URL. If the reply is JSON, a dotted path picks the
/// field; otherwise the body itself is the value. Either way the result is
/// trimmed and cut short, because a note that overruns the lens is worse than
/// no note at all.
abstract final class CardSource {
  /// Longer than this cannot be read on the glasses anyway.
  static const int maxLength = 120;

  /// Walks a dotted path such as `main.temp` or `list.0.name`.
  static String? extract(Object? document, String? path) {
    if (document == null) return null;

    Object? current = document;
    if (path != null && path.trim().isNotEmpty) {
      for (final segment in path.split('.')) {
        final key = segment.trim();
        if (key.isEmpty) continue;

        if (current is Map && current.containsKey(key)) {
          current = current[key];
        } else if (current is List) {
          final index = int.tryParse(key);
          if (index == null || index < 0 || index >= current.length) {
            return null;
          }
          current = current[index];
        } else {
          return null;
        }
      }
    }

    // A whole object is not something a lens can show; only a leaf is.
    if (current == null || current is Map || current is List) return null;

    return clamp(current.toString());
  }

  /// Trims and shortens a value to something a lens can show.
  static String clamp(String value) {
    final collapsed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength - 1)}…';
  }
}
