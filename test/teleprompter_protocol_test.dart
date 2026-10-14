import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/teleprompter.dart';

/// The bytes the official Even app 1.6.5 builds for its teleprompter, as
/// read in its decompiled `Proto` class. See docs/PROTOCOL_NOTES.md.
void main() {
  group('start frame', () {
    test('a single-packet screen carries the trailer and the mode bit', () {
      const text = 'Hello\nWorld\n';
      final frame = TeleprompterProtocol.start(
        seq: 0,
        packetCount: 1,
        packetIndex: 1,
        mode: TeleprompterMode.manual,
        progress: 100,
        text: text,
      );

      expect(frame.sublist(0, 12), [
        0x09, 0x20, 0x00, // command, length 12 + 12 + 8 = 32
        0x00, 0x01, // sequence, start
        0x01, 0x00, 0x01, 0x00, // one packet, this is packet 1
        0x01, // countdown 0, sent as 0 + 1
        0x81, // 0x80 | manual
        0x64, // progress 100
      ]);
      expect(utf8.decode(frame.sublist(12, 24)), text);
      expect(frame.sublist(24), List.filled(8, 0));
      expect(frame.length, 32);
    });

    test('following the voice is announced as mode 2', () {
      final frame = TeleprompterProtocol.start(
        seq: 0,
        packetCount: 1,
        packetIndex: 1,
        mode: TeleprompterMode.voiceFollow,
        progress: 0,
        text: '',
      );
      expect(frame[10], 0x82);
    });

    test('only the last packet of a screen is closed by the trailer', () {
      final first = TeleprompterProtocol.start(
        seq: 4,
        packetCount: 2,
        packetIndex: 1,
        mode: TeleprompterMode.timed,
        progress: 0,
        countdownSeconds: 3,
        text: 'abc',
      );

      expect(first.length, 15);
      expect(first[1], 15);
      expect(first.sublist(5, 12), [0x02, 0x00, 0x01, 0x00, 0x04, 0x80, 0x00]);
    });

    test('the sequence byte wraps at 255, not 256', () {
      Iterable<int> seqOf(int seq) => [
            TeleprompterProtocol.start(
              seq: seq,
              packetCount: 1,
              packetIndex: 1,
              mode: TeleprompterMode.manual,
              progress: 0,
              text: '',
            )[3],
          ];

      expect(seqOf(254), [254]);
      expect(seqOf(255), [0]);
      expect(seqOf(300), [45]);
    });
  });

  group('screen frame', () {
    test('a one-row move asks for the animated scroll', () {
      final frame = TeleprompterProtocol.screen(
        seq: 9,
        packetCount: 1,
        packetIndex: 1,
        progress: 42,
        text: 'x\n',
        scrolled: true,
      );

      expect(frame.sublist(0, 12),
          [0x09, 22, 0x00, 9, 0x07, 1, 0, 1, 0, 42, 0, 0]);
    });

    test('anything else is a plain screen', () {
      final frame = TeleprompterProtocol.screen(
        seq: 9,
        packetCount: 2,
        packetIndex: 2,
        progress: 250,
        text: '',
      );

      expect(frame[4], 0x03);
      expect(frame[9], 100, reason: 'progress is clamped to a percentage');
    });
  });

  test('stop, pause and heartbeat', () {
    expect(TeleprompterProtocol.stop(3), [0x09, 0x06, 0x00, 0x03, 0x05, 0x01]);

    expect(
      TeleprompterProtocol.pause(seq: 7, paused: true, elapsedSeconds: 65),
      [0x24, 0x12, 0x00, 0x07, 0x06, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 65, 0, 0, 0],
    );

    expect(TeleprompterProtocol.heartbeat(256),
        [0x25, 0x06, 0x00, 0x01, 0x04, 0x01]);
  });

  group('answers', () {
    List<int> reply(int sub, {int status = 0}) =>
        [0x09, 0x0A, 0x00, 0x01, sub, 0x01, 0x00, 0x01, 0x00, status];

    test('either screen sub-command answers either screen frame', () {
      expect(TeleprompterProtocol.answers(reply(0x03), 0x07), isTrue);
      expect(TeleprompterProtocol.answers(reply(0x07), 0x03), isTrue);
      expect(TeleprompterProtocol.answers(reply(0x01), 0x03), isFalse);
    });

    test('success is a zero status, not 0xC9', () {
      expect(TeleprompterProtocol.accepted(reply(0x01)), isTrue);
      expect(TeleprompterProtocol.accepted(reply(0x01, status: 0xC9)), isFalse);
      expect(TeleprompterProtocol.accepted([0x09, 0x06]), isFalse);
    });

    test('heartbeat and pause answers', () {
      expect(
          TeleprompterProtocol.answersHeartbeat([0x25, 6, 0, 1, 4, 1]), isTrue);
      expect(TeleprompterProtocol.answersHeartbeat([0x25, 6, 0, 1, 3, 1]),
          isFalse);
      expect(TeleprompterProtocol.answersPause([0x24, 6, 0, 1, 6, 1]), isTrue);
    });
  });

  group('screen packets', () {
    final lines = ['l0', 'l1', 'l2', 'l3', 'l4', 'l5', 'l6'];

    test('five lines go out as three then two', () {
      expect(TeleprompterProtocol.screenPackets(lines, 0),
          ['l0\nl1\nl2\n', 'l3\nl4\n']);
      expect(TeleprompterProtocol.screenPackets(lines, 2),
          ['l2\nl3\nl4\n', 'l5\nl6\n']);
    });

    test('fewer than four lines go out in one packet', () {
      expect(TeleprompterProtocol.screenPackets(lines, 4), ['l4\nl5\nl6\n']);
      expect(TeleprompterProtocol.screenPackets(['only'], 0), ['only\n']);
    });

    test('following the voice counts progress against two lines', () {
      expect(TeleprompterProtocol.progress(0, 2, voiceFollow: true), 100);
      expect(TeleprompterProtocol.progress(4, 12, voiceFollow: true), 40);
    });

    test('progress counts screens, not lines', () {
      expect(TeleprompterProtocol.progress(0, 5), 100);
      expect(TeleprompterProtocol.progress(0, 15), 0);
      expect(TeleprompterProtocol.progress(5, 15), 50);
      expect(TeleprompterProtocol.progress(14, 15), 100);
    });
  });
}
