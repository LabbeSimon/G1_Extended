import 'package:flutter/foundation.dart';

/// What a spoken command turned out to be.
@immutable
class VoiceCommandMatch {
  final VoiceCommandKind kind;

  /// Whatever followed the trigger word, trimmed. Empty for commands that
  /// take no argument.
  final String argument;

  const VoiceCommandMatch(this.kind, this.argument);

  @override
  String toString() => 'VoiceCommandMatch($kind, "$argument")';

  @override
  bool operator ==(Object other) =>
      other is VoiceCommandMatch &&
      other.kind == kind &&
      other.argument == argument;

  @override
  int get hashCode => Object.hash(kind, argument);
}

enum VoiceCommandKind {
  reply,
  weather,
  note,
  clear,
  call,
}

/// Recognises the handful of things worth doing without a round trip to a
/// model.
///
/// Asking a language model to answer "what is the weather" when the app
/// already knows is slow, and asking it to send a text message is not
/// something it can do at all. So a spoken phrase is checked against these
/// first, and only what does not match is treated as a question.
///
/// Matching has to survive a recogniser: accents disappear, punctuation is
/// never produced, and French and English are both likely depending on which
/// microphone was used. So triggers are compared without accents, in both
/// languages, and only at the start of the phrase — "call Simon" is a
/// command, "I will call Simon later" is a sentence.
abstract final class VoiceCommands {
  /// Triggers per command, longest first within each so that "prends note"
  /// wins over "note".
  static const Map<VoiceCommandKind, List<String>> triggers = {
    VoiceCommandKind.reply: [
      'reponds a', 'repond a', 'reponds', 'repond', 'repondre',
      'reply with', 'reply', 'answer with', 'answer',
    ],
    VoiceCommandKind.weather: [
      'quel temps fait il', 'quel temps', 'la meteo', 'meteo',
      'the weather', 'weather forecast', 'weather',
    ],
    VoiceCommandKind.note: [
      'prends note que', 'prends note', 'prend note', 'note que', 'note',
      'take a note', 'remember that', 'remember',
    ],
    VoiceCommandKind.clear: [
      'efface lecran', 'efface', 'ferme', 'annule',
      'clear the screen', 'clear', 'dismiss', 'cancel',
    ],
    VoiceCommandKind.call: [
      'appelle moi', 'appelle', 'appeler', 'appel',
      'call up', 'call', 'phone',
    ],
  };

  /// Commands that mean nothing without something after them.
  static const Set<VoiceCommandKind> requiresArgument = {
    VoiceCommandKind.reply,
    VoiceCommandKind.note,
    VoiceCommandKind.call,
  };

  /// Returns the command a phrase starts with, or null when it is just
  /// something the user said.
  static VoiceCommandMatch? parse(String transcript) {
    final normalised = normalise(transcript);
    if (normalised.isEmpty) return null;

    VoiceCommandMatch? best;
    var bestTriggerLength = 0;

    for (final entry in triggers.entries) {
      for (final trigger in entry.value) {
        if (!_startsWithWord(normalised, trigger)) continue;
        if (trigger.length <= bestTriggerLength) continue;

        final argument = normalised.substring(trigger.length).trim();
        if (argument.isEmpty && requiresArgument.contains(entry.key)) {
          continue;
        }

        bestTriggerLength = trigger.length;
        best = VoiceCommandMatch(entry.key, _restoreFrom(transcript, argument));
      }
    }

    return best;
  }

  /// What to put on the lens when nothing matched.
  ///
  /// "I did not understand" is the least useful sentence an assistant can
  /// say: it spends the whole display telling the wearer something they
  /// already know. What they do not know is what was heard and what they
  /// could have said — and with a closed-vocabulary recogniser, the
  /// vocabulary is exactly the thing to learn.
  ///
  /// So a miss shows the transcript, which usually reveals the problem by
  /// itself, and the commands nearest to what was said. Nearest by first
  /// word, because that is where a command lives and where mishearing
  /// hurts: "appel" against "appelle" is one character and the difference
  /// between working and not.
  static String helpFor(String transcript) {
    final heard = transcript.trim();
    final suggestions = nearestTriggers(heard, count: 3);

    final lines = <String>[
      if (heard.isEmpty) 'Nothing heard' else '"$heard" ?',
      if (suggestions.isNotEmpty) 'Try: ${suggestions.join(' · ')}',
    ];
    return lines.join('\n');
  }

  /// Whether a phrase was probably meant as a command.
  ///
  /// Dictation and commands share one microphone, so the miss must not
  /// hijack ordinary speech: someone dictating a sentence wants their
  /// sentence on the lens, not a menu. A short phrase whose first word is
  /// close to a trigger was an attempt; a long one was speech.
  static bool looksLikeACommandAttempt(String transcript) {
    final words = normalise(transcript).split(' ')
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return false;
    if (words.length > 6) return false;

    for (final trigger in _canonicalTriggers) {
      if (_distance(words.first, trigger.split(' ').first) <= 2) return true;
    }
    return false;
  }

  /// The triggers closest to what was said, best first.
  ///
  /// Exposed for the settings screen, which lists what can be said, and for
  /// tests — the distance is the kind of arithmetic that is confidently
  /// wrong until something checks it.
  static List<String> nearestTriggers(String transcript, {int count = 3}) {
    final spoken = normalise(transcript).split(' ').firstWhere(
          (w) => w.isNotEmpty,
          orElse: () => '',
        );
    if (spoken.isEmpty) return _canonicalTriggers.take(count).toList();

    final scored = <MapEntry<String, int>>[];
    for (final trigger in _canonicalTriggers) {
      final head = trigger.split(' ').first;
      scored.add(MapEntry(trigger, _distance(spoken, head)));
    }

    scored.sort((a, b) {
      final byDistance = a.value.compareTo(b.value);
      // Ties broken alphabetically so the same input never produces two
      // different answers between runs.
      return byDistance != 0 ? byDistance : a.key.compareTo(b.key);
    });

    return [for (final entry in scored.take(count)) entry.key];
  }

  /// One trigger per command, the one worth teaching.
  static const List<String> _canonicalTriggers = [
    'appelle', 'reponds', 'meteo', 'note', 'efface',
  ];

  /// Levenshtein distance, iterative over a single row.
  ///
  /// Words here are short — a command and what was heard instead of it —
  /// so the simple version is the right one.
  static int _distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = substitution < deletion
            ? (substitution < insertion ? substitution : insertion)
            : (deletion < insertion ? deletion : insertion);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }

    return previous[b.length];
  }

  /// True when [text] begins with [trigger] as a whole word, so "notebook"
  /// is not heard as "note".
  static bool _startsWithWord(String text, String trigger) {
    if (!text.startsWith(trigger)) return false;
    if (text.length == trigger.length) return true;
    return text[trigger.length] == ' ';
  }

  /// Takes the argument back from the original text, so a contact keeps its
  /// capitals and a note keeps its accents.
  static String _restoreFrom(String original, String normalisedArgument) {
    if (normalisedArgument.isEmpty) return '';

    final words = original.trim().split(RegExp(r'\s+'));
    final wanted = normalisedArgument.split(' ').length;
    if (wanted >= words.length) return original.trim();

    return words.sublist(words.length - wanted).join(' ');
  }

  /// Lowercases, strips accents and drops punctuation, because none of it
  /// survives speech recognition reliably.
  @visibleForTesting
  static String normalise(String text) {
    const accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyyea';

    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      final index = accented.indexOf(char);
      buffer.write(index >= 0 ? plain[index] : char);
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
