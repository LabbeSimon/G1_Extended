import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// Android's account of an exit, put into words.
class ExitVerdict {
  const ExitVerdict({
    required this.summary,
    required this.explanation,
    this.when,
  });

  final String summary;
  final String explanation;

  /// When the process ended, if Android said.
  final DateTime? when;
}

/// Catches what it can, remembers what it cannot, and offers it back.
///
/// Two kinds of failure end this app, and only one of them can be caught.
/// A Dart exception is catchable and its stack is worth having. A native
/// crash, or a Java error on a platform thread — the LC3 decoder bound under
/// the wrong name was one, the speech model's loader running out of memory
/// another — kills the process outright: no Dart handler runs, and from the
/// user's side the app simply vanishes. The only way to know about the
/// second kind is to notice, on the next launch, that the previous session
/// never said goodbye, and to ask Android what it saw: the Java stack, when
/// there is one, and its own reason for ending the process.
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
    final unclean = await marker.exists();
    final started = unclean ? await marker.lastModified() : null;
    if (unclean) await marker.delete();

    // A Java crash is written down as it happens, so it is known even when
    // the app was in the background and the marker already cleared.
    final javaCrash = await _askAndroid<String>('takeJavaCrash');
    if (!unclean && javaCrash == null) return null;

    final exit = await _askAndroid<Map<Object?, Object?>>('lastExit');
    final verdict = explainExit(
      exit,
      javaCrash: javaCrash,
      sessionStart: started,
    );
    if (verdict == null) return null;

    // The time of death when Android knows it. The marker only says when the
    // session last started, which can be hours earlier.
    final when = verdict.when;
    final detail = StringBuffer()
      ..writeln(verdict.summary)
      ..writeln()
      ..writeln(verdict.explanation)
      ..writeln()
      ..writeln(when != null
          ? 'When: ${when.toIso8601String()}'
          : 'Session started: ${started?.toIso8601String() ?? 'unknown'}');
    if (javaCrash != null) {
      detail
        ..writeln()
        ..writeln(javaCrash.trim());
    }

    return CrashReport(
      when: when ?? started ?? DateTime.now(),
      summary: verdict.summary,
      detail: detail.toString(),
      wasNativeKill: true,
    );
  }

  static const MethodChannel _trail =
      MethodChannel('fr.simonlabbe.g1extended/crash_trail');

  /// One question to the Android side; null when it has no answer, or no
  /// Android side exists, as in tests.
  Future<T?> _askAndroid<T>(String method) async {
    try {
      return await _trail.invokeMethod<T>(method);
    } catch (e) {
      _previousPrint?.call('CrashReporter: $method unavailable: $e',
          wrapWidth: null);
      return null;
    }
  }

  /// Turns what Android recorded about the last exit into what the dialog
  /// says.
  ///
  /// Null when that exit was no failure at all — an update being installed,
  /// the app force-stopped or swiped away — and there is nothing to offer.
  /// A session that ended that way used to be reported as a crash all the
  /// same, since all the marker shows is that it never said goodbye.
  @visibleForTesting
  static ExitVerdict? explainExit(
    Map<Object?, Object?>? exit, {
    String? javaCrash,
    DateTime? sessionStart,
  }) {
    DateTime? when;
    String? reason;
    final timestamp = exit?['timestamp'];
    if (timestamp is int) {
      when = DateTime.fromMillisecondsSinceEpoch(timestamp);
      // An exit from before the session began is an earlier death, not the
      // one being explained.
      if (sessionStart != null &&
          when.isBefore(sessionStart.subtract(const Duration(seconds: 5)))) {
        when = null;
      } else {
        reason = exit?['reason'] as String?;
      }
    }

    final status = exit?['status'];
    final signal = status is int && status != 0 ? status : null;
    final description = reason == null ? null : exit?['description'];
    final android = [
      if (reason != null)
        'Android: $reason${signal == null ? '' : ' (status $signal)'}',
      if (description is String && description.isNotEmpty) description,
    ].join(' — ');
    String withAndroid(String text) =>
        android.isEmpty ? text : '$text\n\n$android';

    if (javaCrash != null) {
      final error = javaCrash
          .split('\n')
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.isNotEmpty && !line.startsWith('Thread:'),
            orElse: () => 'an unknown error',
          );
      return ExitVerdict(
        summary: 'A Java error closed the app: $error',
        explanation: withAndroid(
          'It was raised on a platform thread, where Dart cannot catch it. '
          'The stack is below.',
        ),
        when: when,
      );
    }

    switch (reason) {
      case 'user_requested':
      case 'user_stopped':
      case 'package_updated':
      case 'package_state_change':
      case 'permission_change':
        return null;
      case 'exit_self':
        if (signal == null) return null;
        return ExitVerdict(
          summary: 'The app ended itself (status $signal)',
          explanation: withAndroid('Something in the process called exit.'),
          when: when,
        );
      case 'low_memory':
        final kb = exit?['pssKb'];
        final using = kb is int && kb > 0
            ? ' It was using about ${(kb / 1024).round()} MB.'
            : '';
        return ExitVerdict(
          summary: 'Android closed the app to free memory',
          explanation: withAndroid('The phone ran short of memory.$using'),
          when: when,
        );
      case 'crash_native':
        return ExitVerdict(
          summary: 'A native library crashed'
              '${signal == null ? '' : ' (signal $signal)'}',
          explanation: withAndroid(
            'The crash happened in compiled code — the speech model or the '
            'audio decoder — where Dart cannot catch it.',
          ),
          when: when,
        );
      case 'crash':
        return ExitVerdict(
          summary: 'A Java error closed the app',
          explanation: withAndroid(
            'It was raised on a platform thread, where Dart cannot catch it.',
          ),
          when: when,
        );
      case 'anr':
        return ExitVerdict(
          summary: 'The app stopped responding',
          explanation: withAndroid('Android closed it after it froze.'),
          when: when,
        );
      case null:
        return const ExitVerdict(
          summary: 'The app closed without warning',
          explanation: 'Nothing in Dart caught it: the process was ended from '
              'outside, by Android reclaiming memory or by a native library '
              'failing. This phone did not say which.',
        );
      default:
        return ExitVerdict(
          summary: 'Android ended the app ($reason)',
          explanation: withAndroid('Nothing in the app caught it.'),
          when: when,
        );
    }
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
