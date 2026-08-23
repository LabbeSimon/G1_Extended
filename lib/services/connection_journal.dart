import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every connection event, with its reason, in one place.
///
/// Two betas of this bug have been fought with theories — the handoff, the
/// shared GATT link — and each theory was plausible, partly right, and not
/// the whole story. What has actually fixed things in this codebase, every
/// time, is a capture: the Maps notifications, the battery frames, the
/// voice-note audio. This is the capture for connections.
///
/// Each entry records what happened, in which isolate, and — for
/// disconnections — the reason the platform gives, which names the side
/// that hung up: the glasses, Android, or us. That single field is the
/// difference between knowing and guessing.
///
/// File-backed like every cross-isolate record here, because events happen
/// in both isolates and the report is copied from one.
class ConnectionJournal {
  ConnectionJournal._internal();
  static final ConnectionJournal singleton = ConnectionJournal._internal();
  factory ConnectionJournal() => singleton;

  static const int capacity = 300;

  @visibleForTesting
  static Directory? directoryForTest;

  final Queue<Map<String, Object?>> _events = Queue();
  Timer? _flush;
  bool _loaded = false;

  static String get _isolateName {
    final name = Isolate.current.debugName ?? '';
    if (name.isEmpty || name == 'main') return 'interface';
    return name;
  }

  bool _verbose = false;
  DateTime _verboseCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether the journal records every action, not only connections.
  ///
  /// Ten taps on the Debug screen's title turn it on — the same gesture
  /// that opens developer mode elsewhere, so it is discoverable by the
  /// person it is for and by nobody else. Persisted, because the actions
  /// worth recording happen in the service isolate and the switch is
  /// flipped in the interface; re-read at most every few seconds so a
  /// toggle takes effect without a per-write disk hit.
  Future<bool> verbose() async {
    final now = DateTime.now();
    if (now.difference(_verboseCheckedAt) > const Duration(seconds: 5)) {
      _verboseCheckedAt = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _verbose = prefs.getBool('action_journal_enabled') ?? false;

      // Telemetry someone forgot they turned on stops being telemetry for
      // themselves. A day is enough to catch any bug being chased; after
      // that the journal goes quiet on its own rather than recording a
      // stranger's week — the stranger being future-you.
      if (_verbose) {
        final since = prefs.getInt('action_journal_enabled_at') ?? 0;
        final age = now
            .difference(DateTime.fromMillisecondsSinceEpoch(since));
        if (age > const Duration(hours: 24)) {
          _verbose = false;
          await prefs.setBool('action_journal_enabled', false);
          record('action journal expired after 24h');
        }
      }
    }
    return _verbose;
  }

  Future<void> setVerbose(bool enabled) async {
    _verbose = enabled;
    _verboseCheckedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('action_journal_enabled', enabled);
    if (enabled) {
      await prefs.setInt('action_journal_enabled_at',
          DateTime.now().millisecondsSinceEpoch);
    }
    record(enabled
        ? 'action journal on (expires in 24h)'
        : 'action journal off');
  }

  // What this journal must never hold: content. The write hook records the
  // command byte and the length — that a notification went out, never what
  // it said; that a note was written, never its words. The distinction is
  // what makes an always-off, self-expiring, on-device journal acceptable
  // at all, and any future hook that violates it turns a diagnostic tool
  // into surveillance of the person holding the phone.

  /// Records an action — only when the journal is in verbose mode.
  ///
  /// Fire-and-forget on purpose: an instrument that slows the thing it
  /// measures changes what it measures.
  void action(String what, {Map<String, Object?> detail = const {}}) {
    unawaited(verbose().then((on) {
      if (on) record(what, detail: detail);
    }));
  }

  /// Records one event. [what] is a short verb phrase; [detail] carries
  /// whatever will matter at three in the morning — the side, the reason,
  /// the caller.
  void record(String what, {Map<String, Object?> detail = const {}}) {
    _events.addLast({
      'at': DateTime.now().toIso8601String(),
      'isolate': _isolateName,
      'what': what,
      ...detail,
    });
    while (_events.length > capacity) {
      _events.removeFirst();
    }
    debugPrint('ConnectionJournal[$_isolateName]: $what $detail');
    _scheduleFlush();
  }

  Future<File> _file() async {
    final dir = directoryForTest ?? await getApplicationDocumentsDirectory();
    // One file per isolate: two writers on one file lose each other's
    // entries, and the export merges them by timestamp instead.
    final suffix = _isolateName == 'interface' ? 'ui' : 'svc';
    return File('${dir.path}/connection-journal-$suffix.json');
  }

  void _scheduleFlush() {
    _flush ??= Timer(const Duration(milliseconds: 600), () async {
      _flush = null;
      try {
        final file = await _file();
        await file.writeAsString(jsonEncode(_events.toList()));
      } catch (e) {
        debugPrint('ConnectionJournal: could not persist: $e');
      }
    });
  }

  /// Both isolates' journals, merged in time order.
  Future<String> export() async {
    final merged = <Map<String, Object?>>[];
    final dir = directoryForTest ?? await getApplicationDocumentsDirectory();

    for (final suffix in ['ui', 'svc']) {
      try {
        final file = File('${dir.path}/connection-journal-$suffix.json');
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final raw in decoded) {
            if (raw is Map) merged.add(Map<String, Object?>.from(raw));
          }
        }
      } catch (e) {
        merged.add({'what': 'unreadable journal $suffix', 'error': '$e'});
      }
    }

    merged.sort((a, b) =>
        (a['at'] as String? ?? '').compareTo(b['at'] as String? ?? ''));

    return const JsonEncoder.withIndent('  ').convert({
      'what': 'connection events from both isolates, merged by time',
      'read': 'the "reason" on a disconnect names who hung up: the glasses, '
          'Android, or this app',
      'count': merged.length,
      'events': merged,
    });
  }

  /// Loads this isolate's previous session, so a crash keeps its history.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List && _events.isEmpty) {
        for (final raw in decoded) {
          if (raw is Map) _events.addLast(Map<String, Object?>.from(raw));
        }
        record('journal reloaded after restart');
      }
    } catch (_) {}
  }
}
