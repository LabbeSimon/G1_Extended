import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:path_provider/path_provider.dart';

/// Records what a navigation app's notifications actually contain.
///
/// Every attempt to fix the Maps parsing by reading the code has failed the
/// same way this project's other invisible bugs did: the fields vary by app
/// version, locale and phone, and none of that is visible from here. The
/// instrument is the fix — capture what really arrives on the one phone
/// where it misbehaves, and correct the parser against that, once.
///
/// The frames are mirrored to a file, and that is not a detail: the
/// notification stream is delivered to one Dart isolate — in practice the
/// background service's — while the debug screen reads from the interface
/// isolate. Held in memory alone, the capture filled up in one isolate and
/// was read empty in the other, which is how "nothing captured yet" could
/// stand next to a phone that had just navigated three junctions. The file
/// is the one thing both isolates share.
///
/// Nothing goes anywhere unless the user copies it out of the debug screen
/// themselves.
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
    _scheduleFlush();
  }

  Timer? _flushTimer;

  /// Batches disk writes: Maps rewrites its notification several times a
  /// second near a junction, and one write per rewrite would be busywork.
  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 800), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_frames.toList()));
    } catch (e) {
      debugPrint('NavigationCapture: could not persist: $e');
    }
  }

  /// Brings in whatever another isolate persisted, newest wins.
  ///
  /// Called before reading. The isolate that records is not the one that
  /// exports, so its file is the only view this isolate has.
  Future<void> ensureLoaded() async {
    if (_frames.isNotEmpty) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final frame in decoded) {
        if (frame is Map) _frames.addLast(Map<String, Object?>.from(frame));
      }
    } catch (e) {
      debugPrint('NavigationCapture: could not load: $e');
    }
  }

  /// The capture as a JSON document, ready for a bug report.
  String export() => const JsonEncoder.withIndent('  ').convert({
        'what': 'navigation notifications, exactly as received',
        'count': _frames.length,
        'frames': _frames.toList(),
      });

  Future<void> clear() async {
    _frames.clear();
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nav-capture.json');
  }
}
