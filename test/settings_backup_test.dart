import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/settings_backup.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// The insurance policy, tested as one: what goes out comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('backup-');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    Hive.init(dir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  group('Round trip', () {
    test('preferences, boxes and files survive export and restore', () async {
      SharedPreferences.setMockInitialValues({
        'wake_word': 'souffleur',
        'speedometer_enabled': true,
        'glasses_brightness': 21,
      });
      final blocklist = await Hive.openBox('notificationBlocklist');
      await blocklist.put('com.spam', true);
      File('${dir.path}/notes.json').writeAsStringSync(
          '{"revision":3,"notes":[{"id":"a","title":"code porte",'
          '"body":"4417","updatedAt":0,"pinnedSlot":1}]}');

      final backup = await SettingsBackup.export();

      // A fresh phone.
      SharedPreferences.setMockInitialValues({});
      await blocklist.clear();
      File('${dir.path}/notes.json').deleteSync();

      final summary = await SettingsBackup.restore(backup);
      expect(summary, contains('restored'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wake_word'), 'souffleur');
      expect(prefs.getBool('speedometer_enabled'), isTrue);
      expect(prefs.getInt('glasses_brightness'), 21);
      expect(Hive.box('notificationBlocklist').get('com.spam'), isTrue);
      expect(
        jsonDecode(File('${dir.path}/notes.json').readAsStringSync())['notes'],
        hasLength(1),
      );
    });

    test('the backup is readable JSON with a header a human can check',
        () async {
      final decoded = jsonDecode(await SettingsBackup.export()) as Map;
      expect(decoded['what'], 'G1 Extended settings backup');
      expect(decoded['version'], SettingsBackup.version);
      expect(decoded['exportedAt'], isNotNull);
    });
  });

  group('What never travels', () {
    test('diagnostics consent stays on the phone that gave it', () async {
      SharedPreferences.setMockInitialValues({
        'action_journal_enabled': true,
        'wake_word': 'souffleur',
      });

      final backup = await SettingsBackup.export();
      expect(backup, isNot(contains('action_journal_enabled')),
          reason: 'one yes must not become a permanent yes elsewhere');

      SharedPreferences.setMockInitialValues({});
      await SettingsBackup.restore(backup);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('action_journal_enabled'), isNull);
    });
  });

  group('Refusals a person can act on', () {
    test('not JSON', () async {
      expect(() => SettingsBackup.restore('hello'),
          throwsA(isA<FormatException>()));
    });

    test('JSON that is not a backup', () async {
      expect(() => SettingsBackup.restore('{"a":1}'),
          throwsA(isA<FormatException>()));
    });

    test('a backup from a newer format says "update first"', () async {
      final future = jsonEncode({
        'what': 'G1 Extended settings backup',
        'version': SettingsBackup.version + 1,
      });
      expect(
        () => SettingsBackup.restore(future),
        throwsA(predicate((e) =>
            e is FormatException && e.message.contains('newer'))),
      );
    });
  });
}
