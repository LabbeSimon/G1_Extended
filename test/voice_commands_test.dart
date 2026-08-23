import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/voice_commands.dart';

void main() {
  helpTests();
  attemptTests();
  VoiceCommandMatch? parse(String text) => VoiceCommands.parse(text);

  group('Recognising a command', () {
    test('picks up a French trigger', () {
      expect(parse('météo')?.kind, VoiceCommandKind.weather);
      expect(parse('quel temps fait-il')?.kind, VoiceCommandKind.weather);
      expect(parse('efface')?.kind, VoiceCommandKind.clear);
    });

    test('picks up an English trigger', () {
      expect(parse('weather')?.kind, VoiceCommandKind.weather);
      expect(parse('clear the screen')?.kind, VoiceCommandKind.clear);
    });

    test('captures what follows the trigger', () {
      final match = parse('appelle Simon Labbé');
      expect(match?.kind, VoiceCommandKind.call);
      expect(match?.argument, 'Simon Labbé');
    });

    test('keeps the argument as it was spoken, accents and capitals', () {
      // The trigger is matched without accents, but the argument is a name or
      // a message and must survive intact.
      final match = parse('note que la réunion est déplacée');
      expect(match?.kind, VoiceCommandKind.note);
      expect(match?.argument, 'la réunion est déplacée');
    });

    test('survives a recogniser that drops accents', () {
      expect(parse('repond je suis en route')?.kind, VoiceCommandKind.reply);
      expect(parse('réponds je suis en route')?.kind, VoiceCommandKind.reply);
    });

    test('prefers the longest trigger that fits', () {
      // "prends note" must win over "note", or the argument would start with
      // the word "note".
      final match = parse('prends note acheter du pain');
      expect(match?.kind, VoiceCommandKind.note);
      expect(match?.argument, 'acheter du pain');
    });
  });

  group('Refusing to see a command', () {
    test('leaves an ordinary sentence alone', () {
      expect(parse('what is the capital of France'), isNull);
      expect(parse('explique moi la photosynthèse'), isNull);
    });

    test('only matches at the start of the phrase', () {
      // Otherwise half of what anyone says becomes a command.
      expect(parse('je vais appeler Simon plus tard'), isNull);
      expect(parse('I will call him later'), isNull);
    });

    test('does not match a trigger buried inside a word', () {
      expect(parse('notebook computers are useful'), isNull);
    });

    test('ignores a command that needs an argument and has none', () {
      expect(parse('appelle'), isNull);
      expect(parse('reply'), isNull);
      // Weather needs nothing, so it still counts.
      expect(parse('meteo')?.kind, VoiceCommandKind.weather);
    });

    test('handles an empty or noise-only transcript', () {
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
      expect(parse('[noise]'), isNull);
    });
  });

  group('Normalising a transcript', () {
    test('strips accents', () {
      expect(VoiceCommands.normalise('Réponds à Noël'), 'reponds a noel');
    });

    test('drops the punctuation a recogniser never produces', () {
      expect(VoiceCommands.normalise('Météo, s\'il te plaît.'),
          "meteo s'il te plait");
    });

    test('collapses the tags Vosk emits', () {
      expect(VoiceCommands.normalise('[unk] meteo'), 'meteo');
    });
  });
}

/// What the lens says when nothing matched.
///
/// "I did not understand" spends the whole display telling the wearer
/// something they already know. These pin the alternative: the transcript,
/// which usually reveals the problem by itself, and the commands nearest to
/// what was said — nearest by first word, because that is where a command
/// lives and where mishearing hurts.
void helpTests() {
  group('The nearest commands', () {
    test('a near miss suggests the command it nearly was', () {
      // One character between working and not.
      expect(VoiceCommands.nearestTriggers('appel maman').first, 'appelle');
    });

    test('accents and case do not change the answer', () {
      expect(VoiceCommands.nearestTriggers('MÉTÉO').first, 'meteo');
      expect(VoiceCommands.nearestTriggers('metéo').first, 'meteo');
    });

    test('only the first word is weighed', () {
      // The rest of the phrase is the argument, not the command.
      expect(VoiceCommands.nearestTriggers('note que je dois partir').first,
          'note');
    });

    test('something entirely unrelated still yields suggestions', () {
      final near = VoiceCommands.nearestTriggers('bonjour');
      expect(near, hasLength(3));
    });

    test('the same input always gives the same answer', () {
      // Ties are broken deterministically; a suggestion list that shuffles
      // between identical inputs teaches nothing.
      final first = VoiceCommands.nearestTriggers('zzzz');
      final second = VoiceCommands.nearestTriggers('zzzz');
      expect(first, second);
    });

    test('nothing said yields the commands anyway', () {
      expect(VoiceCommands.nearestTriggers(''), hasLength(3));
    });
  });

  group('The line put on the lens', () {
    test('quotes what was heard, so the mishearing is visible', () {
      final help = VoiceCommands.helpFor('appel maman');
      expect(help, contains('"appel maman"'));
      expect(help, contains('appelle'));
    });

    test('says so plainly when nothing was heard', () {
      expect(VoiceCommands.helpFor('   '), contains('Nothing heard'));
    });

    test('fits the two lines the lens has for it', () {
      final help = VoiceCommands.helpFor('quelque chose de tres tres long');
      expect(help.split('\n'), hasLength(2));
      for (final line in help.split('\n')) {
        expect(line.length, lessThanOrEqualTo(80), reason: line);
      }
    });
  });
}

/// Dictation and commands share one microphone, so the helpful miss must
/// not hijack ordinary speech: someone dictating a sentence wants their
/// sentence on the lens, not a menu of commands.
void attemptTests() {
  group('Telling an attempted command from plain speech', () {
    test('a near miss on a trigger is an attempt', () {
      expect(VoiceCommands.looksLikeACommandAttempt('appel maman'), isTrue);
      expect(VoiceCommands.looksLikeACommandAttempt('metéo'), isTrue);
    });

    test('a long sentence is dictation, however it begins', () {
      expect(
        VoiceCommands.looksLikeACommandAttempt(
            'note bien que je dois passer chez le boulanger avant midi'),
        isFalse,
        reason: 'a dictated sentence must reach the lens as itself',
      );
    });

    test('a phrase unlike any command is not an attempt', () {
      expect(VoiceCommands.looksLikeACommandAttempt('bonjour tout le monde'),
          isFalse);
    });

    test('nothing said is not an attempt', () {
      expect(VoiceCommands.looksLikeACommandAttempt('  '), isFalse);
    });
  });
}
