import 'dart:typed_data';

import 'package:g1_extended/models/g1/commands.dart';
import 'package:flutter/foundation.dart';

class NoteSubCommands {
  static const int REQUEST_AUDIO_INFO = 0x01;
  static const int REQUEST_AUDIO_DATA = 0x02;
  //static const int CREATE_UPDATE_DELETE_NOTE = 0x03; // used for text
  static const int DELETE_AUDIO_STREAM = 0x04;
  static const int DELETE_ALL = 0x05;
}

class VoiceNote {
  int index;
  int? timestamp;
  int? crc;

  VoiceNote({
    required this.index,
    this.timestamp,
    this.crc,
  });

  Uint8List buildFetchCommand(int syncid) {
    return Uint8List.fromList([
      Commands.QUICK_NOTE_ADD,
      0x06,
      0x00,
      syncid,
      NoteSubCommands.REQUEST_AUDIO_DATA,
      index
    ]);
  }

  Uint8List buildDeleteCommand(int syncid) {
    return Uint8List.fromList([
      Commands.QUICK_NOTE_ADD,
      0x06,
      0x00,
      syncid,
      NoteSubCommands.DELETE_AUDIO_STREAM,
      index
    ]);
  }
}

/// Reassembles the audio of one voice note fetched with 0x1E sub 0x02.
///
/// A download arrives as a run of packets
/// `1E len len ? 02 total(LE16) index(LE16) id payload…`. They are kept by
/// their index and joined in order once [total] of them have been counted —
/// which is how the official Even app decides a transfer is done. It never
/// trusts an index to be the last one, only the running count, so a dropped
/// or reordered packet cannot end the transfer early.
class VoiceNoteDownload {
  VoiceNoteDownload(this.id);

  /// The flash id this download asked for. Packets carrying any other id are
  /// not ours and are ignored.
  final int id;

  final Map<int, List<int>> _chunks = {};
  int _total = 0;
  int _received = 0;

  /// Audio the official app drops from the start of every recording: 400
  /// bytes is 200 ms of LC3, the sound of the touch that begins it.
  static const int leadingBytesToDrop = 400;

  /// Header before the audio payload: command, two length bytes, a byte the
  /// app ignores, sub-command, total (LE16), index (LE16), id.
  static const int _headerLength = 10;

  int get total => _total;
  int get received => _received;

  bool get isComplete => _total > 0 && _received >= _total;

  /// Takes one 0x1E packet. Returns true when it was a chunk of this
  /// download — the id has to match and the layout has to hold.
  bool add(List<int> packet) {
    if (packet.length <= _headerLength ||
        packet[0] != Commands.QUICK_NOTE_ADD ||
        packet[4] != NoteSubCommands.REQUEST_AUDIO_DATA ||
        packet[9] != id) {
      return false;
    }

    final total = packet[5] | (packet[6] << 8);
    final index = packet[7] | (packet[8] << 8);
    if (total == 0) return false;

    _total = total;
    _chunks[index] = packet.sublist(_headerLength);
    // Every accepted packet advances the count, duplicates included, exactly
    // as the official app counts them.
    _received++;
    return true;
  }

  /// The joined audio with the opening click removed, as the official app
  /// stores it. Empty until at least one packet has arrived.
  Uint8List get audio {
    final ordered = _chunks.keys.toList()..sort();
    final out = <int>[];
    for (final key in ordered) {
      out.addAll(_chunks[key]!);
    }
    if (out.length > leadingBytesToDrop) {
      return Uint8List.fromList(out.sublist(leadingBytesToDrop));
    }
    return Uint8List.fromList(out);
  }
}

class VoiceNoteNotification {
  Uint8List data;
  List<VoiceNote> entries = [];

  VoiceNoteNotification(this.data) {
    /*
     0 21 
     1 2a = packet length (42)
     2 00 = null
     3 07 = sync id
     4 01 = unknown
     5 04 = num of notes
     6 01 = index
       9a a1 7a 67 = timestamp32
       77 0a 84 bb = crc32
       
       02 
       23 a2 7a 67 
       a9 73 5a a5 
       
       03 
       18 a3 7a 67 
       f1 8f 9e 2c 
       
       04 
       7a a3 7a 67 
       de ef 2a 85
     */
    if (data[0] != Commands.QUICK_NOTE) throw Exception('Invalid command');
    if (data.length < 6) throw Exception('Invalid data length');
    if (data[4] != 0x01) throw Exception('Invalid subcommand');
    int length = data[1] + (data[2] << 8);

    double numNotesLength = (length - 6) / 9;
    if (numNotesLength % 1 != 0) throw Exception('Invalid data length');
    int numNotes = data[5];
    if (numNotes != numNotesLength) throw Exception('Invalid data length');

    for (int i = 0; i < numNotes; i++) {
      int index = data[6 + i * 9];
      List<int> timestampBytes = data.sublist(7 + i * 9, 11 + i * 9);
      int timestamp = timestampBytes[0] +
          (timestampBytes[1] << 8) +
          (timestampBytes[2] << 16) +
          (timestampBytes[3] << 24);

      List<int> crcBytes = data.sublist(11 + i * 9, 15 + i * 9);
      int crc = crcBytes[0] +
          (crcBytes[1] << 8) +
          (crcBytes[2] << 16) +
          (crcBytes[3] << 24);

      entries.add(VoiceNote(index: index, timestamp: timestamp, crc: crc));
    }
  }
}
