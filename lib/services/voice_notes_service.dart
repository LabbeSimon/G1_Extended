import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/voice_note.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';

/// The voice notes recorded on the glasses themselves.
///
/// Holding the right temple records a note in the firmware, and the glasses
/// announce what they hold with an unsolicited 0x21 frame. That listing is
/// documented and parsed. The audio itself is fetched with 0x1E, and the
/// protocol note for that command reads, in full, "TODO".
///
/// So this does the part that is known and measures the part that is not.
/// It parses the listing, asks for each note's audio, and records every
/// frame that comes back — raw, in order, with its length and side. Writing
/// a decoder against a guess is how this codebase has lost days before;
/// writing one against a capture from real glasses has never failed.
class VoiceNotesService {
  VoiceNotesService._internal();
  static final VoiceNotesService singleton = VoiceNotesService._internal();
  factory VoiceNotesService() => singleton;

  /// Frames kept for a report. Enough for a note or two, not a session.
  static const int captureLimit = 400;

  @visibleForTesting
  static Directory? directoryForTest;

  final Queue<Map<String, Object?>> _frames = Queue();
  final List<VoiceNote> _known = [];
  int _sequence = 0;

  final StreamController<List<VoiceNote>> _listings =
      StreamController<List<VoiceNote>>.broadcast();

  /// What the glasses say they are holding, as they say it.
  Stream<List<VoiceNote>> get listings => _listings.stream;

  List<VoiceNote> get known => List.unmodifiable(_known);
  bool get hasCapture => _frames.isNotEmpty;

  /// Handles an unsolicited 0x21 listing.
  void onListing(GlassSide side, List<int> data) {
    _record(side, 'listing', data);

    try {
      final parsed = VoiceNoteNotification(Uint8List.fromList(data));
      _known
        ..clear()
        ..addAll(parsed.entries);

      debugPrint('VoiceNotes: the glasses hold ${parsed.entries.length} note(s)');
      if (!_listings.isClosed) _listings.add(known);
    } catch (e) {
      // A listing we cannot read is worth keeping rather than dropping: the
      // capture is the whole point, and an unparseable frame is the most
      // interesting kind.
      debugPrint('VoiceNotes: unreadable listing ($e) — kept in the capture');
    }
  }

  /// Handles a 0x1E audio frame. Nothing is decoded yet, by design.
  void onAudioFrame(GlassSide side, List<int> data) {
    _record(side, 'audio', data);
  }

  /// Asks the glasses for one note's audio.
  Future<void> fetch(VoiceNote note) async {
    _sequence = (_sequence + 1) & 0xFF;
    final command = note.buildFetchCommand(_sequence);
    _record(GlassSide.left, 'request', command);
    await BluetoothManager.singleton.sendToLeft(command);
  }

  /// Asks for every note the glasses announced, one after another.
  ///
  /// Spaced deliberately: the point is a capture that can be read, and
  /// interleaved replies from four notes would be a puzzle rather than a
  /// measurement.
  Future<void> fetchAll() async {
    for (final note in known) {
      await fetch(note);
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  void _record(GlassSide side, String kind, List<int> data) {
    _frames.addLast({
      'at': DateTime.now().toIso8601String(),
      'side': side.name,
      'kind': kind,
      'length': data.length,
      'bytes': data
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' '),
    });
    while (_frames.length > captureLimit) {
      _frames.removeFirst();
    }
    unawaited(_persist());
  }

  Future<File> _file() async {
    final dir = directoryForTest ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/voice-note-capture.json');
  }

  Timer? _flush;

  /// Written to disk, because the frames arrive in the isolate holding the
  /// link and the report is copied from the one drawing the screen.
  Future<void> _persist() async {
    _flush ??= Timer(const Duration(seconds: 1), () async {
      _flush = null;
      try {
        final file = await _file();
        await file.writeAsString(jsonEncode(_frames.toList()));
      } catch (e) {
        debugPrint('VoiceNotes: could not persist the capture: $e');
      }
    });
  }

  /// The capture as a report, for an issue.
  Future<String> export() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List && decoded.isNotEmpty) {
          return const JsonEncoder.withIndent('  ').convert({
            'what': 'voice note frames, exactly as received',
            'why': 'the 0x1E audio format is undocumented — the protocol '
                'note for it reads "TODO"',
            'count': decoded.length,
            'frames': decoded,
          });
        }
      }
    } catch (e) {
      debugPrint('VoiceNotes: could not read the capture: $e');
    }
    return const JsonEncoder.withIndent('  ').convert({
      'what': 'voice note frames',
      'count': 0,
      'frames': <Object>[],
    });
  }

  Future<void> clear() async {
    _frames.clear();
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
