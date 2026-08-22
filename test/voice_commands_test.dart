import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/voice_commands.dart';

void main() {
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
