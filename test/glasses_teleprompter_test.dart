import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/teleprompter.dart';
import 'package:g1_extended/services/glasses_event_log.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';

/// Answers like the glasses would, unless told otherwise.
class FakeLink implements TeleprompterLink {
  final List<(GlassSide, Uint8List)> sent = [];

  /// Returns the reply for a frame, or null for silence. Defaults to success.
  List<int>? Function(GlassSide side, Uint8List frame) reply = success;

  static List<int>? success(GlassSide side, Uint8List frame) {
    switch (frame[0]) {
      case TeleprompterProtocol.command:
        return [0x09, 0x0A, 0x00, frame[3], frame[4], 1, 0, 1, 0, 0x00];
      case TeleprompterProtocol.heartbeatCommand:
        return [0x25, 0x06, 0x00, frame[3], 0x04, frame[5]];
      case TeleprompterProtocol.pauseCommand:
        return [0x24, 0x06, 0x00, frame[3], 0x06, frame[5]];
    }
    return null;
  }

  @override
  bool isConnected = true;

  @override
  Future<List<int>?> exchange(
    GlassSide side,
    Uint8List frame, {
    required bool Function(List<int> reply) accept,
    required Duration timeout,
  }) async {
    sent.add((side, frame));
    final answer = reply(side, frame);
    return answer != null && accept(answer) ? answer : null;
  }

  List<String> get trace => [
        for (final (side, frame) in sent)
          '${side.name[0]}${frame[0].toRadixString(16)}/${frame[4]}',
      ];
}

List<String> lines(int count) => [for (var i = 0; i < count; i++) 'line $i'];

void main() {
  late FakeLink link;
  late StreamController<GlassesEvent> taps;
  late GlassesTeleprompter teleprompter;

  setUp(() {
    link = FakeLink();
    taps = StreamController<GlassesEvent>.broadcast();
    teleprompter = GlassesTeleprompter(link: link, taps: taps.stream);
  });

  tearDown(() async {
    await teleprompter.stop();
    await taps.close();
  });

  test('every start packet goes left, then right', () async {
    expect(await teleprompter.start(lines(7)), isTrue);

    expect(link.trace, ['l9/1', 'r9/1', 'l9/1', 'r9/1']);
    expect(GlassesTeleprompter.isActive, isTrue);
  });

  test('a refusal on the left keeps the frame from the right', () async {
    link.reply = (side, frame) =>
        [0x09, 0x0A, 0x00, frame[3], frame[4], 1, 0, 1, 0, 0x01];

    expect(await teleprompter.start(lines(3)), isFalse);
    expect(link.trace, ['l9/1']);
    expect(GlassesTeleprompter.isActive, isFalse);
  });

  test('the sequence restarts at zero once the first screen is in', () async {
    await teleprompter.start(lines(7));
    expect([for (final (_, frame) in link.sent) frame[3]], [0, 0, 1, 1]);
    link.sent.clear();

    await teleprompter.nextLine();

    expect([for (final (_, frame) in link.sent) frame[3]], [0, 0, 1, 1]);
  });

  test('moving one line asks for the animated scroll', () async {
    await teleprompter.start(lines(7));
    link.sent.clear();

    await teleprompter.nextLine();

    expect(link.trace, ['l9/7', 'r9/7', 'l9/7', 'r9/7']);
    expect(teleprompter.top.value, 1);
  });

  test('firmware without the animation gets plain screens from then on',
      () async {
    await teleprompter.start(lines(3));
    link.reply = (side, frame) =>
        frame[4] == TeleprompterProtocol.subScreenScrolled
            ? [0x09, 0x0A, 0x00, frame[3], 0x03, 1, 0, 1, 0, 0x01]
            : FakeLink.success(side, frame);
    link.sent.clear();

    await teleprompter.nextLine();
    await teleprompter.nextLine();

    expect(link.trace, ['l9/7', 'l9/3', 'r9/3', 'l9/3', 'r9/3']);
    expect(teleprompter.top.value, 2);
  });

  test('a page move is a plain screen and stops at the last line', () async {
    await teleprompter.start(lines(7));
    link.sent.clear();

    await teleprompter.nextPage();
    expect(teleprompter.top.value, 5);
    expect(link.trace, ['l9/3', 'r9/3']);

    await teleprompter.nextPage();
    expect(teleprompter.top.value, 6);
  });

  test('a temple tap turns the page, a double tap ends the session', () async {
    String? ended;
    teleprompter.onEnded = (reason) => ended = reason;
    await teleprompter.start(lines(12));

    taps.add(GlassesEvent(side: 'right', subcommand: 0x01));
    await pumpEventQueue();
    expect(teleprompter.top.value, 5);

    taps.add(GlassesEvent(side: 'left', subcommand: 0x01));
    await pumpEventQueue();
    expect(teleprompter.top.value, 0);

    taps.add(GlassesEvent(side: 'left', subcommand: 0x00));
    await pumpEventQueue();
    expect(ended, isNotNull);
    expect(teleprompter.isRunning, isFalse);
    expect(GlassesTeleprompter.isActive, isFalse);
  });

  test('stop takes it off both lenses', () async {
    await teleprompter.start(lines(2));
    link.sent.clear();

    await teleprompter.stop();

    expect(link.trace, ['l9/5', 'r9/5']);
    expect(GlassesTeleprompter.isActive, isFalse);
  });

  test('heartbeats go to the right temple every two seconds', () {
    fakeAsync((async) {
      teleprompter.start(lines(2));
      async.flushMicrotasks();
      link.sent.clear();

      async.elapse(const Duration(seconds: 5));

      expect(link.trace, ['r25/4', 'r25/4']);
      teleprompter.stop();
      async.flushMicrotasks();
    });
  });

  test('ten unanswered heartbeats end the session', () {
    fakeAsync((async) {
      String? ended;
      teleprompter.onEnded = (reason) => ended = reason;
      teleprompter.start(lines(2));
      async.flushMicrotasks();
      link.reply = (side, frame) => null;

      async.elapse(const Duration(seconds: 19));
      expect(ended, isNull);

      async.elapse(const Duration(seconds: 2));
      expect(ended, isNotNull);
      expect(teleprompter.isRunning, isFalse);
    });
  });

  test('screens overtaken while one is being sent are dropped', () async {
    await teleprompter.start(lines(20));
    link.sent.clear();

    final first = teleprompter.show(1);
    final second = teleprompter.show(2);
    final third = teleprompter.show(8);
    await Future.wait([first, second, third]);

    expect(teleprompter.top.value, 8);
    expect(link.trace,
        ['l9/7', 'r9/7', 'l9/7', 'r9/7', 'l9/3', 'r9/3', 'l9/3', 'r9/3']);
  });
}
