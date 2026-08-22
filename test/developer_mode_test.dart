import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/developer_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mode = DeveloperMode.singleton;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mode.setEnabled(false);
  });

  test('is off until someone goes looking for it', () async {
    expect(await mode.isEnabled(), isFalse);
  });

  test('unlocks on the tenth tap, not before', () async {
    for (var i = 1; i < DeveloperMode.tapsRequired; i++) {
      final outcome = await mode.registerTap();
      expect(outcome.unlocked, isFalse, reason: 'tap $i should not unlock');
      expect(await mode.isEnabled(), isFalse);
    }

    final last = await mode.registerTap();
    expect(last.unlocked, isTrue);
    expect(await mode.isEnabled(), isTrue);
  });

  test('says nothing for the first few taps, so it stays hidden', () async {
    final early = await mode.registerTap();
    expect(early.message, isNull);
  });

  test('counts down once the user is close', () async {
    for (var i = 0; i < 7; i++) {
      await mode.registerTap();
    }
    final outcome = await mode.registerTap();
    expect(outcome.remaining, 2);
    expect(outcome.message, contains('2'));
  });

  test('further taps do nothing once it is on', () async {
    await mode.setEnabled(true);
    final outcome = await mode.registerTap();
    expect(outcome.alreadyEnabled, isTrue);
    expect(outcome.message, isNull);
  });

  test('turning it off resets the count', () async {
    for (var i = 0; i < 5; i++) {
      await mode.registerTap();
    }
    await mode.setEnabled(false);

    // Five taps banked before the reset must not count towards the next ten.
    for (var i = 1; i < DeveloperMode.tapsRequired; i++) {
      expect((await mode.registerTap()).unlocked, isFalse);
    }
    expect((await mode.registerTap()).unlocked, isTrue);
  });
}
