import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/notification_apps.dart';

/// The glasses drop notifications from any application absent from their
/// allowlist. Sending an empty list with the feature off meant the counter
/// on the lens sat at zero while the phone buzzed all day — no error, no
/// log, just an app that appeared not to forward anything. These pin the
/// list that stops that happening again.
void main() {
  late Directory dir;
  final apps = NotificationApps.singleton;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('notif-apps-');
    NotificationApps.directoryForTest = dir;
    apps.resetForTest();
  });

  tearDown(() {
    NotificationApps.directoryForTest = null;
    apps.resetForTest();
    dir.deleteSync(recursive: true);
  });

  group('Learning which applications exist', () {
    test('the first sighting is reported, so the list can be resent',
        () async {
      expect(await apps.remember('org.signal', 'Signal'), isTrue);
      expect(await apps.remember('org.signal', 'Signal'), isFalse);
    });

    test('an empty package name is not an application', () async {
      expect(await apps.remember('', 'nothing'), isFalse);
      expect(await apps.all(), isEmpty);
    });

    test('the display name follows the latest sighting', () async {
      await apps.remember('org.signal', 'Signal');
      await apps.remember('org.signal', 'Signal Beta');
      expect((await apps.all())['org.signal'], 'Signal Beta');
    });
  });

  group('The allowlist honours exclusions', () {
    test('an excluded application is not offered to the glasses', () async {
      await apps.remember('org.signal', 'Signal');
      await apps.remember('com.spam', 'Spam');

      final allowed = await apps.allowed({'com.spam'});
      expect(allowed.keys, ['org.signal']);
    });

    test('excluding nothing allows everything seen', () async {
      await apps.remember('a', 'A');
      await apps.remember('b', 'B');
      expect((await apps.allowed({})).length, 2);
    });
  });

  group('The list is bounded, oldest sighting first', () {
    test('it stops at capacity', () async {
      for (var i = 0; i < NotificationApps.capacity + 20; i++) {
        await apps.remember('app.$i', 'App $i');
      }
      expect((await apps.all()).length, NotificationApps.capacity);
    });

    test('seeing an old application again saves it from eviction', () async {
      await apps.remember('app.keep', 'Keep');
      for (var i = 0; i < NotificationApps.capacity - 1; i++) {
        await apps.remember('app.$i', 'App $i');
      }
      // One more sighting moves it back to the end of the queue.
      await apps.remember('app.keep', 'Keep');
      for (var i = 0; i < 10; i++) {
        await apps.remember('later.$i', 'Later $i');
      }

      expect((await apps.all()).containsKey('app.keep'), isTrue);
    });
  });

  group('The file bridges the isolates', () {
    test('what one isolate learns, the other sends', () async {
      await apps.remember('org.signal', 'Signal');
      await apps.flushForTest();

      apps.resetForTest();
      expect((await apps.allowed({})).keys, contains('org.signal'));
    });

    test('a damaged store reads as empty rather than throwing', () async {
      File('${dir.path}/notification-apps.json').writeAsStringSync('{oops');
      expect(await apps.all(), isEmpty);
    });
  });
}
