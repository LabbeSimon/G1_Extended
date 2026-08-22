import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';

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
class NotificationHistory {
  NotificationHistory._internal();
  static final NotificationHistory singleton = NotificationHistory._internal();
  factory NotificationHistory() => singleton;

  /// Enough to look back through a short absence, not a reading list.
  static const int capacity = 10;

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
  }

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
  }
}
