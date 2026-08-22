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
