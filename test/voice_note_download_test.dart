import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/voice_note.dart';

/// A download packet: `1E len len seq 02 total(LE16) index(LE16) id payload`.
List<int> packet({
  required int total,
  required int index,
  required int id,
  required List<int> payload,
  int seq = 0,
}) {
  final length = 10 + payload.length;
  return [
    0x1E,
    length & 0xFF,
    (length >> 8) & 0xFF,
    seq,
    0x02,
    total & 0xFF,
    (total >> 8) & 0xFF,
    index & 0xFF,
    (index >> 8) & 0xFF,
    id,
    ...payload,
  ];
}

void main() {
  group('VoiceNoteDownload', () {
    test('joins chunks in index order, not arrival order', () {
      final d = VoiceNoteDownload(7);

      expect(d.add(packet(total: 3, index: 2, id: 7, payload: [0xCC])), isTrue);
      expect(d.add(packet(total: 3, index: 0, id: 7, payload: [0xAA])), isTrue);
      expect(d.isComplete, isFalse);
      expect(d.add(packet(total: 3, index: 1, id: 7, payload: [0xBB])), isTrue);

      expect(d.isComplete, isTrue);
      expect(d.audio, [0xAA, 0xBB, 0xCC]);
    });

    test('completes on the count, not on the last index', () {
      final d = VoiceNoteDownload(1);
      d.add(packet(total: 2, index: 5, id: 1, payload: [0x01]));
      expect(d.isComplete, isFalse);
      d.add(packet(total: 2, index: 9, id: 1, payload: [0x02]));
      expect(d.isComplete, isTrue);
    });

    test('a packet for another recording is refused', () {
      final d = VoiceNoteDownload(7);
      expect(
          d.add(packet(total: 1, index: 0, id: 8, payload: [0x01])), isFalse);
      expect(d.received, 0);
    });

    test('a text-note acknowledgement is refused', () {
      final d = VoiceNoteDownload(7);
      final ack = [0x1E, 0x0A, 0x00, 0x00, 0x03, 1, 0, 1, 0, 7, 0x00];
      expect(d.add(ack), isFalse);
    });

    test('a duplicate still advances the count, as the firmware is believed',
        () {
      final d = VoiceNoteDownload(3);
      d.add(packet(total: 2, index: 0, id: 3, payload: [0x01]));
      d.add(packet(total: 2, index: 0, id: 3, payload: [0x01]));
      expect(d.isComplete, isTrue, reason: 'two accepted packets, total two');
    });

    test('the opening 400 bytes are dropped when there are more', () {
      final d = VoiceNoteDownload(1);
      final body = List<int>.generate(500, (i) => i & 0xFF);
      d.add(packet(total: 1, index: 0, id: 1, payload: body));

      expect(d.audio.length, 100);
      expect(d.audio.first, 400 & 0xFF);
    });

    test('a recording of 400 bytes or fewer is kept whole', () {
      final d = VoiceNoteDownload(1);
      d.add(packet(total: 1, index: 0, id: 1, payload: List.filled(400, 1)));
      expect(d.audio.length, 400);
    });

    test('audio is a Uint8List ready for the decoder', () {
      final d = VoiceNoteDownload(1);
      d.add(packet(total: 1, index: 0, id: 1, payload: [1, 2, 3]));
      expect(d.audio, isA<Uint8List>());
    });
  });
}
