import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/speech_model.dart';
import 'package:g1_extended/services/wake_word_vocabulary.dart';

/// The lists these tests guard were read out of the models' own lexicons, not
/// guessed. The failure they prevent has no symptom: a wake word the model
/// cannot produce leaves an interface that looks configured and detection
/// that never fires.
void main() {
  group('Every model is usable', () {
    test('each has a suggestion list', () {
      for (final model in SpeechModel.all) {
        expect(WakeWordVocabulary.suggestionsFor(model), isNotEmpty,
            reason: '${model.id} offers no wake word at all');
      }
    });

    test('each default is one of its own suggestions', () {
      for (final model in SpeechModel.all) {
        expect(
          WakeWordVocabulary.isVerified(
              WakeWordVocabulary.defaultFor(model), model),
          isTrue,
          reason: '${model.id} defaults to a word it cannot recognise',
        );
      }
    });

    test('suggestions are lower case and free of spaces', () {
      // The grammar is matched against single lower-case tokens; anything
      // else cannot match whatever the recogniser returns.
      for (final model in SpeechModel.all) {
        for (final word in WakeWordVocabulary.suggestionsFor(model)) {
          expect(word, word.toLowerCase(), reason: '$word is not lower case');
          expect(word.contains(' '), isFalse, reason: '$word has a space');
        }
      }
    });

    test('archive URLs point at the model each is named after', () {
      for (final model in SpeechModel.all) {
        expect(model.url, endsWith('${model.id}.zip'),
            reason: '${model.id} would download a different model');
      }
    });

    test('ids are distinct, so the two never share a directory', () {
      final ids = SpeechModel.all.map((m) => m.id).toSet();
      expect(ids, hasLength(SpeechModel.all.length));
    });
  });

  group('Souffleur belongs to French', () {
    test('the French model can return it', () {
      expect(
          WakeWordVocabulary.isVerified('souffleur', SpeechModel.french),
          isTrue);
    });

    test('the English model cannot', () {
      // Not a matter of accuracy: the word is absent from that lexicon, so it
      // is never produced.
      expect(
          WakeWordVocabulary.isVerified('souffleur', SpeechModel.english),
          isFalse);
    });

    test('and the interface can say which model would work', () {
      expect(WakeWordVocabulary.modelProviding('souffleur')?.language, 'fr');
    });

    test('it is the French default', () {
      expect(WakeWordVocabulary.defaultFor(SpeechModel.french), 'souffleur');
    });
  });

  group('Matching is forgiving about how the word is typed', () {
    test('case and stray spaces do not matter', () {
      expect(WakeWordVocabulary.isVerified('  Souffleur ', SpeechModel.french),
          isTrue);
    });

    test('an unknown word is reported as unverified rather than accepted', () {
      expect(WakeWordVocabulary.isVerified('xyzzy', SpeechModel.french),
          isFalse);
      expect(WakeWordVocabulary.modelProviding('xyzzy'), isNull);
    });
  });

  group('Looking up a model by id', () {
    test('finds each of them', () {
      for (final model in SpeechModel.all) {
        expect(SpeechModel.byId(model.id).id, model.id);
      }
    });

    test('falls back to English rather than throwing', () {
      // A preference written by an older version names a model that no longer
      // exists; refusing to start over it would be worse than reverting.
      expect(SpeechModel.byId('vosk-model-that-was-removed').id,
          SpeechModel.english.id);
    });
  });
}
