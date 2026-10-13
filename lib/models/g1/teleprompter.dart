import 'dart:convert';
import 'dart:typed_data';

/// How the start frame tells the glasses the script will move.
enum TeleprompterMode {
  /// The phone scrolls it at a set pace.
  timed(0),

  /// The reader moves it, by taps or from the phone.
  manual(1),

  /// The official app's voice-following mode. Its screens carry a highlight
  /// position whose exact meaning is not established, so this app follows
  /// the voice itself and announces [manual] instead.
  voiceFollow(2);

  const TeleprompterMode(this.wire);

  final int wire;
}

/// The glasses' own teleprompter: command 0x09, with 0x24 (pause) and 0x25
/// (heartbeat).
///
/// Not in `Even Realities G1 BLE Protocol.txt`. Reverse-engineered from the
/// official Even app 1.6.5 (its `Proto` and `Telepromt` classes, decompiled);
/// the frames are documented in docs/PROTOCOL_NOTES.md and have not been
/// checked against a capture yet.
abstract final class TeleprompterProtocol {
  static const int command = 0x09;
  static const int pauseCommand = 0x24;
  static const int heartbeatCommand = 0x25;

  static const int subStart = 0x01;
  static const int subRunDot = 0x02;
  static const int subScreen = 0x03;
  static const int subStop = 0x05;

  /// A screen that moved by one row, which recent firmware animates.
  static const int subScreenScrolled = 0x07;

  static const int _subPause = 0x06;
  static const int _subHeartbeat = 0x04;

  /// Lines on the lens at once.
  static const int visibleLines = 5;

  static const int _headerLength = 12;

  /// Zero bytes closing the last packet of a screen, counted in its length.
  static const int _trailerLength = 8;

  /// The first packet of a screen, which may be followed by a second one.
  static Uint8List start({
    required int seq,
    required int packetCount,
    required int packetIndex,
    required TeleprompterMode mode,
    required int progress,
    required String text,
    int countdownSeconds = 0,
  }) =>
      _textFrame(
        seq: seq,
        sub: subStart,
        packetCount: packetCount,
        packetIndex: packetIndex,
        fields: [countdownSeconds + 1, 0x80 | mode.wire, _percent(progress)],
        text: text,
      );

  /// A new screen while the teleprompter runs.
  static Uint8List screen({
    required int seq,
    required int packetCount,
    required int packetIndex,
    required int progress,
    required String text,
    bool scrolled = false,
  }) =>
      _textFrame(
        seq: seq,
        sub: scrolled ? subScreenScrolled : subScreen,
        packetCount: packetCount,
        packetIndex: packetIndex,
        fields: [_percent(progress), 0, 0],
        text: text,
      );

  static Uint8List stop(int seq) =>
      Uint8List.fromList([command, 0x06, 0x00, seq % 255, subStop, 0x01]);

  static Uint8List pause({
    required int seq,
    required bool paused,
    required int elapsedSeconds,
  }) {
    final frame = ByteData(18)
      ..setUint8(0, pauseCommand)
      ..setUint16(1, 18, Endian.little)
      ..setUint8(3, seq % 255)
      ..setUint8(4, _subPause)
      ..setUint8(5, paused ? 1 : 0)
      ..setUint32(14, elapsedSeconds, Endian.little);
    return frame.buffer.asUint8List();
  }

  /// Sent to the right temple every two seconds while the teleprompter runs.
  static Uint8List heartbeat(int seq) {
    final s = seq % 255;
    return Uint8List.fromList(
        [heartbeatCommand, 0x06, 0x00, s, _subHeartbeat, s]);
  }

  /// Whether [reply] answers a 0x09 frame of sub-command [sub]. Either screen
  /// sub-command answers either screen frame.
  static bool answers(List<int> reply, int sub) {
    if (reply.length < 5 || reply[0] != command) return false;
    final got = reply[4];
    if (sub == subScreen || sub == subScreenScrolled) {
      return got == subScreen || got == subScreenScrolled;
    }
    return got == sub;
  }

  /// Whether the glasses took a start or screen frame. Unlike most commands
  /// they answer 0x00 for success here, not 0xC9.
  static bool accepted(List<int> reply) => reply.length > 9 && reply[9] == 0;

  static bool answersHeartbeat(List<int> reply) =>
      reply.length > 5 &&
      reply[0] == heartbeatCommand &&
      reply[4] == _subHeartbeat;

  static bool answersPause(List<int> reply) =>
      reply.length > 5 && reply[0] == pauseCommand && reply[4] == _subPause;

  /// The text of the packets that put [visibleLines] lines from [top] on the
  /// lens: one packet when fewer than four remain, otherwise three lines and
  /// then two. Every line ends with a newline.
  static List<String> screenPackets(List<String> lines, int top) {
    final window = lines.skip(top.clamp(0, lines.length)).toList();
    String join(Iterable<String> part) => part.map((l) => '$l\n').join();
    if (window.length < 4) return [join(window)];
    return [join(window.take(3)), join(window.skip(3).take(2))];
  }

  /// The scroll position the glasses draw, 0 to 100.
  static int progress(int top, int lineCount) {
    if (lineCount <= visibleLines) return 100;
    return _percent(100 * top ~/ (lineCount - visibleLines));
  }

  static int _percent(int value) => value.clamp(0, 100);

  static Uint8List _textFrame({
    required int seq,
    required int sub,
    required int packetCount,
    required int packetIndex,
    required List<int> fields,
    required String text,
  }) {
    final body = utf8.encode(text);
    final last = packetIndex == packetCount;
    final length = _headerLength + body.length + (last ? _trailerLength : 0);
    final frame = BytesBuilder(copy: false)
      ..add([
        command,
        length & 0xFF,
        (length >> 8) & 0xFF,
        seq % 255,
        sub,
        packetCount & 0xFF,
        (packetCount >> 8) & 0xFF,
        packetIndex & 0xFF,
        (packetIndex >> 8) & 0xFF,
        for (final field in fields) field & 0xFF,
      ])
      ..add(body);
    if (last) frame.add(Uint8List(_trailerLength));
    return frame.toBytes();
  }
}
