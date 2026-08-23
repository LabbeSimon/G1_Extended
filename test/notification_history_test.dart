import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/notification_history.dart';

RecalledNotification at(String title, DateTime when) => RecalledNotification(
      app: 'Messages',
      title: title,
      body: 'body',
      at: when,
    );

void main() {
  group('Laying a notification out for the lens', () {
    final now = DateTime(2026, 8, 22, 17, 0);

    test('names the app and how long ago', () {
      final line = at('Hello', now.subtract(const Duration(minutes: 5)))
          .forGlasses(now: now);
      expect(line, startsWith('Messages · 5m ago'));
      expect(line, contains('Hello'));
    });

    test('says now for something that just arrived', () {
      expect(
        at('Hi', now).forGlasses(now: now),
        startsWith('Messages · now'),
      );
    });

    test('switches to hours and days as time passes', () {
      expect(at('a', now.subtract(const Duration(hours: 3)))
          .forGlasses(now: now), contains('3h ago'));
      expect(at('a', now.subtract(const Duration(days: 2)))
          .forGlasses(now: now), contains('2d ago'));
    });

  });

  group('Recalling', () {
    late NotificationHistory history;

    setUp(() {
      history = NotificationHistory.singleton;
      history.clear();
    });

    test('gives nothing when nothing has arrived', () {
      expect(history.recallNext(), isNull);
    });

    test('walks backwards on repeated taps', () {
      final base = DateTime(2026, 8, 22, 17, 0);
      for (final name in ['first', 'second', 'third']) {
        history.rememberForTest(at(name, base));
      }

      // Newest first, then further back on each tap.
      expect(history.recallNext(now: base)?.title, 'third');
      expect(history.recallNext(now: base.add(const Duration(seconds: 2)))
          ?.title, 'second');
      expect(history.recallNext(now: base.add(const Duration(seconds: 4)))
          ?.title, 'first');
    });

    test('wraps round rather than going silent past the oldest', () {
      final base = DateTime(2026, 8, 22, 17, 0);
      history.rememberForTest(at('only', base));

      expect(history.recallNext(now: base)?.title, 'only');
      expect(history.recallNext(now: base.add(const Duration(seconds: 2)))
          ?.title, 'only');
    });

    test('starts from the newest again after a pause', () {
      final base = DateTime(2026, 8, 22, 17, 0);
      history.rememberForTest(at('older', base));
      history.rememberForTest(at('newer', base));

      expect(history.recallNext(now: base)?.title, 'newer');
      expect(history.recallNext(now: base.add(const Duration(seconds: 2)))
          ?.title, 'older');

      // A tap much later means "show me the latest", not "carry on".
      expect(
        history.recallNext(now: base.add(const Duration(minutes: 5)))?.title,
        'newer',
      );
    });

    test('forgets what is too old to be worth recalling', () {
      final base = DateTime(2026, 8, 22, 17, 0);
      history.rememberForTest(at('ancient', base));

      final muchLater = base.add(NotificationHistory.keepFor +
          const Duration(minutes: 1));
      expect(history.recallNext(now: muchLater), isNull);
    });

    test('keeps only the most recent few', () {
      final base = DateTime(2026, 8, 22, 17, 0);
      for (var i = 0; i < NotificationHistory.capacity + 5; i++) {
        history.rememberForTest(at('n$i', base));
      }
      expect(history.items.length, NotificationHistory.capacity);
      expect(history.items.first.title,
          'n${NotificationHistory.capacity + 4}');
    });
  });

  group('The file bridges the isolates', () {
    late Directory dir;
    final history = NotificationHistory.singleton;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notif-hist-');
      NotificationHistory.directoryForTest = dir;
      history.resetForTest();
      history.clear();
    });

    tearDown(() {
      NotificationHistory.directoryForTest = null;
      history.resetForTest();
      dir.deleteSync(recursive: true);
    });

    test('what one life records, the next life reads', () async {
      // Life one: the isolate that receives notifications.
      history.rememberForTest(RecalledNotification(
        app: 'Signal',
        title: 'Léa',
        body: 'on se voit à 18h ?',
        at: DateTime.now(),
      ));
      await history.flushForTest();

      // Life two: the isolate holding the glasses, born empty.
      history.resetForTest();
      await history.ensureLoaded();

      final recalled = history.recallNext();
      expect(recalled, isNotNull,
          reason: '"Nothing recent" on a phone that buzzed all morning '
              'is the bug this exists to prevent');
      expect(recalled!.body, 'on se voit à 18h ?');
    });

    test('expiry applies on load too — a six hour old file is not news',
        () async {
      history.rememberForTest(RecalledNotification(
        app: 'Old',
        title: 'stale',
        body: 'stale',
        at: DateTime.now().subtract(const Duration(hours: 7)),
      ));
      await history.flushForTest();
      history.resetForTest();

      await history.ensureLoaded();
      expect(history.recallNext(), isNull);
    });

    test('a damaged file reads as empty, never as a crash', () async {
      File('${dir.path}/notification-history.json')
          .writeAsStringSync('{not json');
      await history.ensureLoaded();
      expect(history.isEmpty, isTrue);
    });

    test('clearing clears the file as well, not just the memory', () async {
      history.rememberForTest(RecalledNotification(
        app: 'A', title: 't', body: 'b', at: DateTime.now(),
      ));
      await history.flushForTest();

      history.clear();
      // give the async flush a beat
      await Future<void>.delayed(const Duration(milliseconds: 50));

      history.resetForTest();
      await history.ensureLoaded();
      expect(history.isEmpty, isTrue,
          reason: 'a cleared history that resurrects from its mirror was '
              'not cleared');
    });
  });

}