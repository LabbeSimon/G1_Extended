import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The applications the glasses have been told about.
///
/// The firmware keeps its own allowlist and drops notifications from
/// anything absent from it. That is not a preference this app can decline
/// to use: sending an empty list with the feature switched off — on the
/// reasoning that the phone should filter alone — means the glasses discard
/// every notification and their counter sits at zero, which is precisely
/// what happened.
///
/// So the list is kept, and kept honest: every application seen posting a
/// notification is remembered here, and the allowlist sent to the glasses
/// is that set minus whatever the wearer excluded. The phone still filters
/// first, immediately; the firmware list exists to stop the glasses
/// second-guessing it.
///
/// File-backed, because the isolate receiving notifications is not always
/// the one holding the link.
class NotificationApps {
  NotificationApps._internal();
  static final NotificationApps singleton = NotificationApps._internal();
  factory NotificationApps() => singleton;

  /// The firmware's packet is chunked at 176 bytes and its own capacity is
  /// unknown, so the list is bounded. Least recently seen goes first.
  static const int capacity = 80;

  @visibleForTesting
  static Directory? directoryForTest;

  /// package name to display name, insertion-ordered by last seen.
  final Map<String, String> _apps = {};
  bool _loaded = false;
  DateTime? _seenAt;
  Timer? _flushTimer;

  Future<File> _file() async {
    final dir = directoryForTest ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/notification-apps.json');
  }

  Future<void> _load() async {
    final file = await _file();
    if (!await file.exists()) {
      _loaded = true;
      return;
    }

    final modified = await file.lastModified();
    if (_loaded && _seenAt != null && !modified.isAfter(_seenAt!)) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _apps.clear();
        decoded.forEach((key, value) {
          if (key is String && value is String) _apps[key] = value;
        });
      }
      _seenAt = modified;
    } catch (e) {
      debugPrint('NotificationApps: unreadable store: $e');
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      final temporary = File('${file.path}.writing');
      await temporary.writeAsString(jsonEncode(_apps), flush: true);
      await temporary.rename(file.path);
      _seenAt = await file.lastModified();
    } catch (e) {
      debugPrint('NotificationApps: could not save: $e');
    }
  }

  /// Records an application. Returns true when it had never been seen —
  /// the caller resends the allowlist, so the *next* notification from it
  /// gets through rather than the app being invisible until a resync.
  Future<bool> remember(String packageName, String displayName) async {
    if (packageName.isEmpty) return false;
    await _load();

    final isNew = !_apps.containsKey(packageName);

    // Re-inserting moves it to the end, which is what makes eviction
    // "least recently seen" rather than "first ever seen".
    _apps.remove(packageName);
    _apps[packageName] = displayName;

    while (_apps.length > capacity) {
      _apps.remove(_apps.keys.first);
    }

    _scheduleFlush();
    return isNew;
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_save());
    });
  }

  /// Everything seen, minus [excluded]. What the glasses are told.
  Future<Map<String, String>> allowed(Set<String> excluded) async {
    await _load();
    return {
      for (final entry in _apps.entries)
        if (!excluded.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<Map<String, String>> all() async {
    await _load();
    return Map.unmodifiable(_apps);
  }

  @visibleForTesting
  Future<void> flushForTest() => _save();

  @visibleForTesting
  void resetForTest() {
    _apps.clear();
    _loaded = false;
    _seenAt = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
