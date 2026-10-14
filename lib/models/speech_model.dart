/// The offline speech models the app can install.
///
/// There is more than one because recognition is closed-vocabulary: Vosk can
/// only ever return words that exist in the model it was built with. A word
/// outside that lexicon is not merely recognised poorly, it can never be
/// produced at all — so the choice of model decides which wake words are
/// possible, and which language dictation understands.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.language,
    required this.languageLabel,
    required this.url,
    required this.approximateBytes,
  });

  /// Directory name on disk; also the archive's single top-level directory.
  final String id;

  /// ISO 639-1 code, used to pick the matching wake-word vocabulary.
  final String language;

  /// The locale handed to the phone's own recogniser, so the chosen language
  /// drives phone-microphone dictation as well as the offline Vosk model.
  String get localeId => switch (language) {
        'fr' => 'fr_FR',
        _ => 'en_US',
      };

  /// Shown in the interface.
  final String languageLabel;

  final String url;

  /// Used to warn about the download before it starts. Approximate on
  /// purpose: the real figure comes from the response, this is only for the
  /// label beforehand.
  final int approximateBytes;

  static const english = SpeechModel(
    id: 'vosk-model-small-en-us-0.15',
    language: 'en',
    languageLabel: 'English',
    url:
        'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
    approximateBytes: 41 * 1000 * 1000,
  );

  static const french = SpeechModel(
    id: 'vosk-model-small-fr-0.22',
    language: 'fr',
    languageLabel: 'Français',
    url: 'https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip',
    approximateBytes: 42 * 1000 * 1000,
  );

  static const all = <SpeechModel>[english, french];

  static SpeechModel byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => english);

  /// The model for a phone language such as `fr_FR`; English when there is
  /// none for it.
  static SpeechModel forLocale(String locale) {
    final language = locale.split(RegExp('[_-]')).first.toLowerCase();
    return all.firstWhere((m) => m.language == language, orElse: () => english);
  }

  @override
  String toString() => '$id ($language)';
}
