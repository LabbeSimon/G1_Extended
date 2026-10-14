import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/settings_backup.dart';
import 'package:g1_extended/services/voice_commands.dart';

/// What reaches an assistant, and what a backup carries.
///
/// Both of these were silent failures rather than errors: a question that
/// quietly never left the phone, and a restore that quietly repaired the
/// glasses to a stranger's temples.
void main() {
  group('house triggers do not cover ordinary questions', () {
    // The point of the fix in DictationService: these are exactly the
    // sentences Home Assistant handles well and the trigger list misses.
    // If someone later widens the triggers, this test says what that
    // changes rather than letting it pass unnoticed.
    const questions = [
      'quelle est la capitale du perou',
      'combien de temps pour cuire un oeuf',
      'how long should i boil an egg',
      'who wrote the moonlight sonata',
    ];

    for (final question in questions) {
      test('"$question" is not a house command', () {
        expect(VoiceCommands.parse(question)?.kind,
            isNot(VoiceCommandKind.house));
      });
    }

    test('an imperative still is one', () {
      expect(VoiceCommands.parse('eteins la lumiere du salon')?.kind,
          VoiceCommandKind.house);
      expect(VoiceCommands.parse('turn off the hall light')?.kind,
          VoiceCommandKind.house);
    });
  });

  group('a backup does not carry the pairing', () {
    test('the glasses identity keys are held back', () {
      // Reached through the export so the test pins the behaviour, not the
      // shape of a private list.
      for (final key in ['left', 'right', 'leftName', 'rightName']) {
        expect(SettingsBackup.carries(key), isFalse,
            reason: '$key would repair another install to these temples');
      }
    });

    test('ordinary settings still travel', () {
      expect(SettingsBackup.carries('glasses_brightness'), isTrue);
      expect(SettingsBackup.carries('use_glasses_microphone'), isTrue);
    });
  });
}
