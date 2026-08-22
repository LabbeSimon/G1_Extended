import 'package:g1_extended/models/speech_model.dart';

/// Wake words that the installed speech model can actually produce.
///
/// This exists because of a failure mode with no symptom. Vosk recognises
/// against a fixed lexicon; a word outside it is not returned with low
/// confidence, it is never returned. Setting such a word as the wake word
/// leaves an interface that looks configured, a microphone that is genuinely
/// listening, and detection that cannot fire — no error, no warning, nothing
/// to debug.
///
/// The lists below were taken from the lexicons of the models themselves
/// rather than from what seemed likely, because that guess is exactly the one
/// that fails silently.
class WakeWordVocabulary {
  const WakeWordVocabulary._();

  /// Suggestions per model language, all verified present in that lexicon.
  static const Map<String, List<String>> suggestions = {
    'en': ['computer', 'mirador', 'beacon', 'lantern', 'prism'],
    'fr': ['souffleur', 'vigie', 'mirador', 'besicles', 'ordinateur'],
  };

  /// The word used when nothing has been chosen, per language.
  static const Map<String, String> defaults = {
    'en': 'computer',
    'fr': 'souffleur',
  };

  static List<String> suggestionsFor(SpeechModel model) =>
      suggestions[model.language] ?? const ['computer'];

  static String defaultFor(SpeechModel model) =>
      defaults[model.language] ?? 'computer';

  /// Whether [word] is one this model is known to be able to return.
  ///
  /// A word absent from this list is not necessarily impossible — the English
  /// lexicon holds some two hundred thousand entries and these are five of
  /// them. It means only that it has not been verified, which is worth saying
  /// plainly rather than letting the user discover it by a wake word that
  /// never fires.
  static bool isVerified(String word, SpeechModel model) =>
      suggestionsFor(model).contains(word.trim().toLowerCase());

  /// The model whose lexicon contains [word], if one of them does.
  ///
  /// Lets the interface answer the useful question — "souffleur needs the
  /// French model" — instead of the useless one, "that will not work".
  static SpeechModel? modelProviding(String word) {
    final needle = word.trim().toLowerCase();
    for (final model in SpeechModel.all) {
      if (suggestionsFor(model).contains(needle)) return model;
    }
    return null;
  }
}
