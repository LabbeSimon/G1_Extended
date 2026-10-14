import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/voice_note.dart';
import 'package:g1_extended/models/g1/commands.dart';

void main() {
  group('VoiceNote', () {
    test('buildFetchCommand returns correct Uint8List', () {
      final voiceNote = VoiceNote(index: 1);
      final syncid = 2;
      final expected = Uint8List.fromList([
        Commands.QUICK_NOTE_ADD,
        0x06,
        0x00,
        syncid,
        NoteSubCommands.REQUEST_AUDIO_DATA,
        1
      ]);

      final result = voiceNote.buildFetchCommand(syncid);

      expect(result, expected);
    });

    test('buildDeleteCommand returns correct Uint8List', () {
      final voiceNote = VoiceNote(index: 1);
      final syncid = 2;
      final expected = Uint8List.fromList([
        Commands.QUICK_NOTE_ADD,
        0x06,
        0x00,
        syncid,
        NoteSubCommands.DELETE_AUDIO_STREAM,
        1
      ]);

      final result = voiceNote.buildDeleteCommand(syncid);

      expect(result, expected);
    });
  });

  group('Asking for the list', () {
    test('is 0x1E sub 0x01 with a constant 0x01, as the official app sends',
        () {
      expect(VoiceNote.buildListCommand(5), [0x1E, 0x06, 0x00, 5, 0x01, 0x01]);
    });

    test('wraps its sequence at 255', () {
      expect(VoiceNote.buildListCommand(255)[3], 0);
    });

    test('the answer under 0x1E parses like a 0x21 announcement', () {
      final reply = Uint8List.fromList([
        0x1E, 0x0F, 0x00, 0x03, 0x01, 0x01, // header, one recording
        0x02, 0x9a, 0xa1, 0x7a, 0x67, 0x77, 0x0a, 0x84, 0xbb,
      ]);
      final list = VoiceNoteNotification(reply);
      expect(list.entries.single.index, 2);
      expect(list.entries.single.timestamp, 1736090010);
    });

    test('an empty flash answers with no entries', () {
      final reply = Uint8List.fromList([0x1E, 0x06, 0x00, 0x03, 0x01, 0x00]);
      expect(VoiceNoteNotification(reply).entries, isEmpty);
    });
  });

  group('VoiceNoteNotification', () {
    test('parses data correctly', () {
      final data = Uint8List.fromList([
        0x21,
        0x2a,
        0x00,
        0x07,
        0x01,
        0x04,
        0x01,
        0x9a,
        0xa1,
        0x7a,
        0x67,
        0x77,
        0x0a,
        0x84,
        0xbb,
        0x02,
        0x23,
        0xa2,
        0x7a,
        0x67,
        0xa9,
        0x73,
        0x5a,
        0xa5,
        0x03,
        0x18,
        0xa3,
        0x7a,
        0x67,
        0xf1,
        0x8f,
        0x9e,
        0x2c,
        0x04,
        0x7a,
        0xa3,
        0x7a,
        0x67,
        0xde,
        0xef,
        0x2a,
        0x85
      ]);

      final notification = VoiceNoteNotification(data);

      expect(notification.entries.length, 4);
      expect(notification.entries[0].index, 1);
      expect(notification.entries[1].index, 2);
      expect(notification.entries[2].index, 3);
      expect(notification.entries[3].index, 4);

      expect(notification.entries[0].timestamp, 1736090010);
      expect(notification.entries[1].timestamp, 1736090147);
      expect(notification.entries[2].timestamp, 1736090392);
      expect(notification.entries[3].timestamp, 1736090490);
    });

    test('throws exception on invalid data length', () {
      final data = Uint8List.fromList([
        Commands.QUICK_NOTE,
        0x0e,
        0x00,
        0x02,
        0x01,
        0x01,
        0x01,
        0xfc,
        0x57,
        0x78,
        0x67,
        0x81,
        0xa3,
        0x75
      ]);

      expect(() => VoiceNoteNotification(data), throwsException);
    });
  });
}
