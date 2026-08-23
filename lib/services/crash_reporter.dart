import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What the app knows about the last time it stopped unexpectedly.
class CrashReport {
  const CrashReport({
    required this.when,
    required this.summary,
    required this.detail,
    required this.wasNativeKill,
  });

  final DateTime when;

  /// One line, for the dialog title area.
  final String summary;

  /// The whole thing, for the clipboard.
  final String detail;

  /// True when nothing in Dart caught it — the process was killed outright,
  /// which is what a failing native library looks like from here.
  final bool wasNativeKill;
}

/// Catches what it can, remembers what it cannot, and offers it back.
///
/// Two kinds of failure end this app, and only one of them can be caught.
/// A Dart exception is catchable and its stack is worth having. A native
/// crash — the speech model's loader is the one that has actually happened
/// here — kills the process outright: no handler runs, nothing is written,
/// and from the user's side the app simply vanishes. The only way to know
/// about the second kind is to notice, on the next launch, that the previous
/// session never said goodbye.
///
/// Both leave a report behind, and the report is offered on the next launch
/// with the two things worth doing about it: copy it, and reconnect.
class CrashReporter {
  CrashReporter._internal();
  static final CrashReporter singleton = CrashReporter._internal();
  factory CrashReporter() => singleton;

  static const String _crashFile = 'last-crash.txt';
  static const String _sessionMarker = 'session-running';

  /// How many log lines to keep. Enough to see what led up to it without
  /// holding the whole session in memory.
  static const int _logLines = 400;

  final Queue<String> _log = Queue<String>();
  DebugPrintCallback? _previousPrint;
  bool _installed = false;

  /// The report waiting to be shown, if any. Read once at start-up.
  CrashReport? pending;

  /// Starts catching. Call before anything else in main.
  Future<void> install() async {
    if (_installed) return;
    _installed = true;

    _previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _remember(message);
      _previousPrint?.call(message, wrapWidth: wrapWidth);
    };

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(_write(
        summary: details.exceptionAsString(),
        stack: details.stack?.toString() ?? '',
        native: false,
      ));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(_write(
        summary: error.toString(),
        stack: stack.toString(),
        native: false,
      ));
      return false;
    };
  }

  /// Reads whatever the previous session left, and starts a new one.
  ///
  /// Must run after [install] and before the first frame, so the interface
  /// can offer the report as soon as there is somewhere to show it.
  Future<void> begin() async {
    pending = await _readPending();
    await markSessionRunning();
  }

  /// Says that a session is under way.
  ///
  /// Written at start-up and again on every return to the foreground, since
  /// [markCleanExit] removes it each time the app is backgrounded. Separate
  /// from [begin] so resuming does not re-read, and re-offer, a report the
  /// user has already dealt with.
  Future<void> markSessionRunning() async {
    final marker = await _file(_sessionMarker);
    await marker.writeAsString(DateTime.now().toIso8601String());
  }

  /// Records that this session ended on purpose.
  ///
  /// Its absence next time is what tells us the process was killed.
  Future<void> markCleanExit() async {
    final marker = await _file(_sessionMarker);
    if (await marker.exists()) await marker.delete();
  }

  /// Forgets the pending report, once the user has dealt with it.
  Future<void> dismiss() async {
    pending = null;
    final file = await _file(_crashFile);
    if (await file.exists()) await file.delete();
  }

  void _remember(String message) {
    _log.addLast(message);
    while (_log.length > _logLines) {
      _log.removeFirst();
    }
  }

  Future<CrashReport?> _readPending() async {
    final crash = await _file(_crashFile);
    if (await crash.exists()) {
      final text = await crash.readAsString();
      return CrashReport(
        when: await crash.lastModified(),
        summary: text.split('\n').firstWhere(
              (line) => line.trim().isNotEmpty,
              orElse: () => 'The app stopped unexpectedly',
            ),
        detail: text,
        wasNativeKill: false,
      );
    }

    // No crash file, but the previous session never cleared its marker: the
    // process was killed without Dart getting a word in.
    final marker = await _file(_sessionMarker);
    if (!await marker.exists()) return null;

    final started = await marker.lastModified();
    await marker.delete();

    return CrashReport(
      when: started,
      summary: 'The app closed without warning',
      detail: _compose(
        summary: 'The app closed without warning.\n\n'
            'Nothing in Dart caught it, which means the process was ended '
            'from outside — either by Android reclaiming memory, or by a '
            'native library failing. The speech model loader is the known '
            'cause of the second kind.',
        stack: '',
        started: started,
      ),
      wasNativeKill: true,
    );
  }

  Future<void> _write({
    required String summary,
    required String stack,
    required bool native,
  }) async {
    try {
      final file = await _file(_crashFile);
      await file.writeAsString(_compose(
        summary: summary,
        stack: stack,
        started: DateTime.now(),
      ));
    } catch (e) {
      // Writing the crash report must never itself be the crash.
      _previousPrint?.call('CrashReporter: could not write report: $e', wrapWidth: null);
    }
  }

  String _compose({
    required String summary,
    required String stack,
    required DateTime started,
  }) {
    final buffer = StringBuffer()
      ..writeln(summary)
      ..writeln()
      ..writeln('When: ${started.toIso8601String()}');

    if (stack.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stack:')
        ..writeln(stack.trim());
    }

    if (_log.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Last ${_log.length} log lines:')
        ..writeAll(_log, '\n');
    }

    return buffer.toString();
  }

  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }
}
