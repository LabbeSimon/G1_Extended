import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/services/crash_reporter.dart';

/// What the crash dialog says, from what Android recorded about the exit.
void main() {
  final start = DateTime(2026, 10, 14, 10, 30, 54);
  final later = DateTime(2026, 10, 14, 10, 31, 20).millisecondsSinceEpoch;

  Map<Object?, Object?> exit(String reason, {int status = 0}) => {
        'timestamp': later,
        'reason': reason,
        'status': status,
        'description': null,
        'pssKb': 512000,
      };

  test('an update or a force stop is not a crash', () {
    for (final reason in [
      'package_updated',
      'user_stopped',
      'user_requested',
      'permission_change',
    ]) {
      expect(
        CrashReporter.explainExit(exit(reason), sessionStart: start),
        isNull,
        reason: reason,
      );
    }
  });

  test('a Java error names itself and keeps the time of death', () {
    final verdict = CrashReporter.explainExit(
      exit('crash'),
      javaCrash: 'Thread: main\n\njava.lang.UnsatisfiedLinkError: No '
          'implementation found for byte[] Cpp.decodeLC3(byte[])\n'
          '\tat fr.simonlabbe.g1extended.cpp.Cpp.decodeLC3(Native Method)',
      sessionStart: start,
    )!;

    expect(verdict.summary, startsWith('A Java error closed the app: '
        'java.lang.UnsatisfiedLinkError'));
    expect(verdict.when, DateTime.fromMillisecondsSinceEpoch(later));
  });

  test('memory and native crashes say which', () {
    expect(
      CrashReporter.explainExit(exit('low_memory'), sessionStart: start)!
          .explanation,
      contains('about 500 MB'),
    );
    expect(
      CrashReporter.explainExit(exit('crash_native', status: 11),
              sessionStart: start)!
          .summary,
      'A native library crashed (signal 11)',
    );
  });

  test('an exit older than the session explains nothing', () {
    final old = {
      ...exit('crash_native', status: 11),
      'timestamp': DateTime(2026, 10, 13).millisecondsSinceEpoch,
    };
    final verdict = CrashReporter.explainExit(old, sessionStart: start)!;

    expect(verdict.summary, 'The app closed without warning');
    expect(verdict.when, isNull);
  });

  test('without Android\'s account, the old message stands', () {
    expect(
      CrashReporter.explainExit(null, sessionStart: start)!.summary,
      'The app closed without warning',
    );
  });
}
