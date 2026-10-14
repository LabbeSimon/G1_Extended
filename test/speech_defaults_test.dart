import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/speech_model.dart';
import 'package:g1_extended/services/dictation_service.dart';

void main() {
  test('the offline model follows the phone language until one is chosen', () {
    expect(SpeechModel.forLocale('fr_FR'), SpeechModel.french);
    expect(SpeechModel.forLocale('fr-CA'), SpeechModel.french);
    expect(SpeechModel.forLocale('en_US'), SpeechModel.english);
    expect(SpeechModel.forLocale('de_DE'), SpeechModel.english);
  });

  test('the chosen language drives the phone recogniser locale too', () {
    expect(SpeechModel.french.localeId, 'fr_FR');
    expect(SpeechModel.english.localeId, 'en_US');
  });

  group('The touchpad records first, then transcribes', () {
    test('through the glasses microphone by default', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DictationService.usesGlassesMicrophone(), isTrue);
    });

    test('unless the phone microphone was chosen', () async {
      SharedPreferences.setMockInitialValues({
        DictationService.glassesMicrophoneKey: false,
      });
      expect(await DictationService.usesGlassesMicrophone(), isFalse);
    });
  });
}
