import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/services/voice_commands.dart';

/// Speaking to the house has to coexist with the commands that were already
/// there, and with the fact that Home Assistant wants the sentence whole.
void main() {
  VoiceCommandMatch? parse(String text) => VoiceCommands.parse(text);

  group('Recognising something meant for the house', () {
    test('an English instruction is recognised', () {
      expect(parse('turn off the hall light')?.kind, VoiceCommandKind.house);
      expect(parse('turn on the kitchen')?.kind, VoiceCommandKind.house);
    });

    test('a French instruction is recognised, accents or not', () {
      expect(parse('allume la cuisine')?.kind, VoiceCommandKind.house);
      expect(parse('éteins le salon')?.kind, VoiceCommandKind.house);
      expect(parse('eteins le salon')?.kind, VoiceCommandKind.house);
    });

    test('a question about the house is recognised too', () {
      expect(parse('is the front door locked')?.kind, VoiceCommandKind.house);
    });
  });

  group('What gets sent', () {
    test('the whole sentence goes across, verb included', () {
      // Stripping "turn off" would remove the only word saying what to do.
      expect(parse('turn off the hall light')?.argument,
          'turn off the hall light');
    });

    test('the original wording is preserved, accents and case', () {
      expect(parse('Éteins le Salon')?.argument, 'Éteins le Salon');
    });

    test('a trigger with nothing after it is not a command', () {
      expect(parse('allume')?.kind, isNot(VoiceCommandKind.house));
      expect(parse('turn on'), isNull);
    });
  });

  group('Living alongside the commands that were already there', () {
    test('"ferme" alone still clears the screen', () {
      expect(parse('ferme')?.kind, VoiceCommandKind.clear);
    });

    test('closing the shutters wins over clearing the screen', () {
      // Longest trigger wins, which is why this one is spelled out in full.
      expect(parse('ferme les volets')?.kind, VoiceCommandKind.house);
      expect(parse('ferme les volets')?.argument, 'ferme les volets');
    });

    test('taking a note is untouched', () {
      expect(parse('prends note que le lait est fini')?.kind,
          VoiceCommandKind.note);
    });

    test('the weather is still answered by the phone', () {
      expect(parse('quel temps fait il')?.kind, VoiceCommandKind.weather);
    });

    test('calling someone is still a call', () {
      expect(parse('appelle Simon')?.kind, VoiceCommandKind.call);
    });

    test('an ordinary sentence is still not a command', () {
      expect(parse('I was thinking about turning on the heating'), isNull);
      expect(parse('what is the capital of Peru'), isNull);
    });
  });
}
