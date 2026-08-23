import 'dart:collection';
import 'dart:convert';

import 'package:notification_listener_service/notification_event.dart';

/// Records what a navigation app's notifications actually contain.
///
/// Every attempt to fix the Maps parsing by reading the code has failed the
/// same way this project's other invisible bugs did: the fields vary by app
/// version, locale and phone, and none of that is visible from here. The
/// instrument is the fix — capture what really arrives on the one phone
/// where it misbehaves, and correct the parser against that, once.
///
/// Everything stays in memory and goes nowhere unless the user copies it
/// out of the debug screen themselves.
class NavigationCapture {
  NavigationCapture._internal();
  static final NavigationCapture singleton = NavigationCapture._internal();
  factory NavigationCapture() => singleton;

  /// Enough for a few junctions' worth of rewrites, which Maps issues
  /// several times each.
  static const int capacity = 60;

  final Queue<Map<String, Object?>> _frames = Queue();

  bool get isEmpty => _frames.isEmpty;
  int get length => _frames.length;

  /// Records one notification as raw material.
  ///
  /// Only fields, never interpretation: the entire point is to see what the
  /// parser would have seen, not what it made of it.
  void record(ServiceNotificationEvent notification, {required bool ongoing}) {
    _frames.addLast({
      'at': DateTime.now().toIso8601String(),
      'package': notification.packageName,
      'id': notification.id,
      'title': notification.title,
      'content': notification.content,
      'ongoing': ongoing,
      'removed': notification.hasRemoved,
      'canReply': notification.canReply,
    });
    while (_frames.length > capacity) {
      _frames.removeFirst();
    }
  }

  /// The capture as a JSON document, ready for a bug report.
  String export() => const JsonEncoder.withIndent('  ').convert({
        'what': 'navigation notifications, exactly as received',
        'count': _frames.length,
        'frames': _frames.toList(),
      });

  void clear() => _frames.clear();
}
