import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:path_provider/path_provider.dart';

/// A notification as it was when it arrived.
@immutable
class RecalledNotification {
  final String app;
  final String title;
  final String body;
  final DateTime at;

  const RecalledNotification({
    required this.app,
    required this.title,
    required this.body,
    required this.at,
  });

  /// One notification, laid out for a lens rather than a phone.
  String forGlasses({DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(at);
    final when = elapsed.inMinutes < 1
        ? 'now'
        : elapsed.inMinutes < 60
            ? '${elapsed.inMinutes}m ago'
            : elapsed.inHours < 24
                ? '${elapsed.inHours}h ago'
                : '${elapsed.inDays}d ago';

    final head = [app, when].where((p) => p.isNotEmpty).join(' · ');
    return [head, title, body]
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }
}

/// Keeps recent notifications so they can be called back to the lens.
///
/// A notification is shown once and then gone; if the wearer was walking, or
/// simply looking elsewhere, it is lost. Tapping a temple to see it again is
/// the obvious remedy, and the gesture is free: a tap sends a release without
/// a preceding hold, which the dictation handler ignores.
///
/// Repeated taps walk back through the list, which is why the cursor exists.
/// It resets after a pause so a tap tomorrow shows today's newest, not
/// wherever the wearer stopped scrolling yesterday.
///
/// The list is mirrored to a file, and that is load-bearing: the
/// notification stream reaches one Dart isolate while the temple tap is
/// handled in whichever isolate holds the glasses. Held in memory alone,
/// the history filled up on one side and the tap recalled from an empty
/// list on the other — "Nothing recent" on a phone that had buzzed all
/// morning. The file is what the isolates share; it lives in app-private
/// storage and follows the same six-hour expiry as the memory.
class NotificationHistory {
  NotificationHistory._internal();
  static final NotificationHistory singleton = NotificationHistory._internal();
  factory NotificationHistory() => singleton;

  /// Sized for the history screen, which shows everything held here.
  ///
  /// The temple-tap walk is unaffected by the size: the cursor wraps at the
  /// end of whatever exists, and nobody taps fifty times. What the larger
  /// figure buys is the screen answering "what did I miss this afternoon"
  /// rather than only "what did I miss just now".
  static const int capacity = 50;

  /// Older than this and the wearer means "the latest one", not "the one I
  /// was on".
  static const Duration cursorTimeout = Duration(seconds: 20);

  /// Notifications older than this are not worth recalling.
  static const Duration keepFor = Duration(hours: 6);

  final Queue<RecalledNotification> _items = Queue<RecalledNotification>();

  int _cursor = 0;
  DateTime? _lastRecall;

  UnmodifiableListView<RecalledNotification> get items =>
      UnmodifiableListView(_items.toList().reversed.toList());

  bool get isEmpty => _items.isEmpty;

  void remember(ServiceNotificationEvent notification, String appName) {
    if (notification.hasRemoved == true) return;

    final title = notification.title?.trim() ?? '';
    final body = notification.content?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    _items.addLast(RecalledNotification(
      app: appName,
      title: title,
      body: body,
      at: DateTime.now(),
    ));

    while (_items.length > capacity) {
      _items.removeFirst();
    }

    // A new arrival makes the cursor meaningless.
    _cursor = 0;
    _lastRecall = null;

    _scheduleFlush();
  }

  Timer? _flushTimer;
  bool _loaded = false;

  /// Where the mirror lives. Overridable so tests need no platform channel.
  @visibleForTesting
  static Directory? directoryForTest;

  static Future<File> _file() async {
    final dir =
        directoryForTest ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/notification-history.json');
  }

  /// Batched: a chatty group conversation would otherwise write the file
  /// once per message.
  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode([
        for (final item in _items)
          {
            'app': item.app,
            'title': item.title,
            'body': item.body,
            'at': item.at.toIso8601String(),
          },
      ]));
    } catch (e) {
      debugPrint('NotificationHistory: could not persist: $e');
    }
  }

  /// Brings in what the other isolate recorded. Called before any read;
  /// cheap after the first time.
  Future<void> ensureLoaded({DateTime? now}) async {
    if (_loaded) return;
    _loaded = true;
    if (_items.isNotEmpty) return;

    try {
      final file = await _file();
      if (!await file.exists()) return;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;

      final cutoff = (now ?? DateTime.now()).subtract(keepFor);
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final at = DateTime.tryParse(raw['at'] as String? ?? '');
        if (at == null || at.isBefore(cutoff)) continue;
        _items.addLast(RecalledNotification(
          app: raw['app'] as String? ?? '',
          title: raw['title'] as String? ?? '',
          body: raw['body'] as String? ?? '',
          at: at,
        ));
      }
      while (_items.length > capacity) {
        _items.removeFirst();
      }
    } catch (e) {
      debugPrint('NotificationHistory: could not load: $e');
    }
  }

  /// For tests that build several lives of the same singleton.
  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _cursor = 0;
    _lastRecall = null;
    _loaded = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Writes now, for tests that read the file straight after remembering.
  @visibleForTesting
  Future<void> flushForTest() => _flush();

  /// The next notification to show, walking backwards on repeated taps.
  ///
  /// Returns null when there is nothing recent to show.
  RecalledNotification? recallNext({DateTime? now}) {
    final at = now ?? DateTime.now();

    _items.removeWhere((item) => at.difference(item.at) > keepFor);
    if (_items.isEmpty) return null;

    final continuing =
        _lastRecall != null && at.difference(_lastRecall!) <= cursorTimeout;

    _cursor = continuing ? _cursor + 1 : 0;
    _lastRecall = at;

    final ordered = _items.toList().reversed.toList();
    // Past the oldest, start again at the newest rather than going silent.
    if (_cursor >= ordered.length) _cursor = 0;

    return ordered[_cursor];
  }

  /// Inserts a ready-made entry. The production path builds one from an
  /// Android event, which a unit test cannot construct meaningfully.
  @visibleForTesting
  void rememberForTest(RecalledNotification notification) {
    _items.addLast(notification);
    while (_items.length > capacity) {
      _items.removeFirst();
    }
    _cursor = 0;
    _lastRecall = null;
  }

  void clear() {
    _items.clear();
    _cursor = 0;
    _lastRecall = null;
    unawaited(_flush());
  }
}
