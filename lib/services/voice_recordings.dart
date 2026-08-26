import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:g1_extended/utils/wav.dart';

/// Where a recording came from.
enum RecordingSource {
  /// Held the right temple; the firmware recorded it to its own flash and
  /// the phone fetched it afterwards.
  glassesNote,

  /// Held a temple with the glasses microphone streaming live to the phone.
  glassesLive,

  /// The phone's own microphone.
  phone,
}

/// What is actually in the file on disk.
enum RecordingFormat {
  /// Playable anywhere: 16 kHz mono PCM in a RIFF container.
  wav,

  /// The codec bytes exactly as the glasses sent them, kept because
  /// decoding failed. Not playable yet, but it is the recording, and a
  /// decoder that works can be pointed at it later.
  lc3,
}

/// One kept recording.
class Recording {
  final String id;
  final String fileName;
  final DateTime capturedAt;
  final Duration duration;
  final int byteLength;
  final RecordingSource source;
  final RecordingFormat format;

  /// Filled in once speech recognition has run, empty until then and
  /// possibly forever — a recording is worth keeping without one.
  final String transcript;

  /// Why there is no transcript, when there is a reason worth showing.
  final String? transcriptError;

  const Recording({
    required this.id,
    required this.fileName,
    required this.capturedAt,
    required this.duration,
    required this.byteLength,
    required this.source,
    required this.format,
    this.transcript = '',
    this.transcriptError,
  });

  bool get isPlayable => format == RecordingFormat.wav;
  bool get hasTranscript => transcript.trim().isNotEmpty;

  Recording copyWith({
    String? transcript,
    String? transcriptError,
    bool clearError = false,
  }) =>
      Recording(
        id: id,
        fileName: fileName,
        capturedAt: capturedAt,
        duration: duration,
        byteLength: byteLength,
        source: source,
        format: format,
        transcript: transcript ?? this.transcript,
        transcriptError:
            clearError ? null : (transcriptError ?? this.transcriptError),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'capturedAt': capturedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'byteLength': byteLength,
        'source': source.name,
        'format': format.name,
        'transcript': transcript,
        if (transcriptError != null) 'transcriptError': transcriptError,
      };

  static Recording? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final fileName = raw['fileName'];
    if (id is! String || id.isEmpty) return null;
    if (fileName is! String || fileName.isEmpty) return null;

    return Recording(
      id: id,
      fileName: fileName,
      capturedAt: DateTime.tryParse(raw['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(milliseconds: (raw['durationMs'] as num?)?.toInt() ?? 0),
      byteLength: (raw['byteLength'] as num?)?.toInt() ?? 0,
      source: RecordingSource.values.firstWhere(
        (s) => s.name == raw['source'],
        orElse: () => RecordingSource.glassesNote,
      ),
      format: RecordingFormat.values.firstWhere(
        (f) => f.name == raw['format'],
        orElse: () => RecordingFormat.wav,
      ),
      transcript: raw['transcript'] as String? ?? '',
      transcriptError: raw['transcriptError'] as String?,
    );
  }
}

/// Keeps the audio itself, not only what was recognised in it.
///
/// The app used to decode a voice note, transcribe it, keep the text and
/// drop the samples on the floor. That made every failure downstream —
/// no speech model installed, a word Vosk did not know, an exception in
/// the recogniser — silently destroy something a person had said out loud
/// and could not say again. Worse, the note was deleted off the glasses'
/// flash *before* any of that ran, so there was nothing left to retry from.
///
/// So the order here is deliberate and is the whole point of this class:
/// **the audio reaches disk before anything else is allowed to happen.**
/// Transcription is a decoration applied afterwards, and its failure is
/// recorded next to the recording rather than replacing it.
///
/// Stored as files plus a JSON index rather than in Hive, for the reason
/// [NotesLibrary] documents: Hive is per-isolate, the background service is
/// the isolate that holds the glasses, and two Hive handles over one box
/// lose each other's writes. A directory and an index re-read on mtime is
/// what the two isolates can actually share.
class VoiceRecordings {
  VoiceRecordings._internal();
  static final VoiceRecordings singleton = VoiceRecordings._internal();
  factory VoiceRecordings() => singleton;

  static const String _folderName = 'voice_recordings';
  static const String _indexName = 'index.json';

  /// A ceiling so a talkative week cannot fill the phone. Generous on
  /// purpose: at 16 kHz mono this is several hours of speech.
  static const int maxBytesOnDisk = 512 * 1024 * 1024;

  /// And a floor on count, so the byte cap can never wipe the list down to
  /// nothing after one very long recording.
  static const int minKept = 20;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires whenever a recording is added, annotated or removed.
  Stream<void> get changes => _changes.stream;

  /// Overridable so tests need no platform channel.
  @visibleForTesting
  static Directory? directoryForTest;

  final Map<String, Recording> _entries = {};
  DateTime? _seenAt;
  bool _loaded = false;

  Future<Directory> _folder() async {
    final base = directoryForTest ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _index() async => File('${(await _folder()).path}/$_indexName');

  /// The file holding [recording], whether or not it still exists.
  Future<File> fileFor(Recording recording) async =>
      File('${(await _folder()).path}/${recording.fileName}');

  Future<void> _load({bool force = false}) async {
    final file = await _index();

    if (!await file.exists()) {
      _loaded = true;
      return;
    }

    final modified = await file.lastModified();
    if (!force && _loaded && _seenAt != null && !modified.isAfter(_seenAt!)) {
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      _entries.clear();
      final list = decoded['recordings'];
      if (list is List) {
        for (final raw in list) {
          final entry = Recording.fromMap(raw);
          if (entry != null) _entries[entry.id] = entry;
        }
      }
      _seenAt = modified;
      _loaded = true;
    } catch (e) {
      // An unreadable index must not cost us the audio: the files are still
      // on disk, and [recoverOrphans] can put them back in the list.
      debugPrint('VoiceRecordings: unreadable index, starting empty: $e');
      _loaded = true;
    }
  }

  Future<void> _saveIndex() async {
    final file = await _index();
    final temporary = File('${file.path}.writing');

    final payload = jsonEncode({
      'recordings': [for (final e in _entries.values) e.toMap()],
    });

    try {
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
      _seenAt = await file.lastModified();
    } catch (e) {
      debugPrint('VoiceRecordings: could not write the index: $e');
    }
  }

  /// Writes decoded PCM as a playable WAV and returns the stored recording.
  ///
  /// Throws if the audio could not be written. Callers are expected to let
  /// that propagate rather than swallow it: a caller that carries on after
  /// a failed save is about to delete the only other copy off the glasses.
  Future<Recording> savePcm(
    Uint8List pcm, {
    required RecordingSource source,
    DateTime? capturedAt,
    int sampleRate = Wav.defaultSampleRate,
  }) async {
    if (pcm.isEmpty) throw ArgumentError('Refusing to store an empty recording');

    final wav = Wav.fromPcm16(pcm, sampleRate: sampleRate);
    return _store(
      bytes: wav,
      extension: 'wav',
      format: RecordingFormat.wav,
      source: source,
      capturedAt: capturedAt ?? DateTime.now(),
      duration: Wav.durationOfPcm16(pcm.length, sampleRate: sampleRate),
    );
  }

  /// Keeps the undecoded codec bytes when LC3 decoding gave us nothing.
  ///
  /// Not playable, and deliberately kept anyway. The alternative is
  /// discarding the only copy of something that was said because one
  /// native call returned an empty buffer.
  Future<Recording> saveUndecodedLc3(
    Uint8List encoded, {
    required RecordingSource source,
    DateTime? capturedAt,
  }) async {
    if (encoded.isEmpty) {
      throw ArgumentError('Refusing to store an empty recording');
    }

    return _store(
      bytes: encoded,
      extension: 'lc3',
      format: RecordingFormat.lc3,
      source: source,
      capturedAt: capturedAt ?? DateTime.now(),
      duration: Duration.zero,
      transcriptError: 'Audio could not be decoded; kept as raw LC3.',
    );
  }

  Future<Recording> _store({
    required Uint8List bytes,
    required String extension,
    required RecordingFormat format,
    required RecordingSource source,
    required DateTime capturedAt,
    required Duration duration,
    String? transcriptError,
  }) async {
    await _load();

    final id = _newId();
    final fileName = '$id.$extension';
    final folder = await _folder();
    final target = File('${folder.path}/$fileName');
    final temporary = File('${target.path}.writing');

    // Write then rename, so a crash mid-write leaves no half file that the
    // index would claim is a recording.
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);

    final entry = Recording(
      id: id,
      fileName: fileName,
      capturedAt: capturedAt,
      duration: duration,
      byteLength: bytes.length,
      source: source,
      format: format,
      transcriptError: transcriptError,
    );

    _entries[id] = entry;
    await _saveIndex();
    await _enforceCap();
    _emit();

    debugPrint(
      'VoiceRecordings: kept $fileName '
      '(${bytes.length} bytes, ${duration.inMilliseconds}ms, ${source.name})',
    );
    return entry;
  }

  /// Attaches recognised text to a recording already on disk.
  Future<void> attachTranscript(String id, String transcript) async {
    await _load();
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(transcript: transcript.trim(), clearError: true);
    await _saveIndex();
    _emit();
  }

  /// Records why a recording has no text, without touching the audio.
  Future<void> attachTranscriptError(String id, String reason) async {
    await _load();
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(transcriptError: reason);
    await _saveIndex();
    _emit();
  }

  /// Newest first.
  Future<List<Recording>> all() async {
    await _load();
    final entries = _entries.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return entries;
  }

  Future<Recording?> byId(String id) async {
    await _load();
    return _entries[id];
  }

  /// Deletes a recording and its file. Only ever called from the interface,
  /// on something a person chose to remove.
  Future<void> remove(String id) async {
    await _load();
    final entry = _entries.remove(id);
    if (entry == null) return;
    try {
      final file = await fileFor(entry);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('VoiceRecordings: could not delete ${entry.fileName}: $e');
    }
    await _saveIndex();
    _emit();
  }

  Future<int> totalBytes() async {
    await _load();
    return _entries.values.fold<int>(0, (sum, e) => sum + e.byteLength);
  }

  /// Puts audio files back in the index when the index was lost.
  ///
  /// The files are the recording; the index is only a description of them.
  /// If the description is damaged, rebuild it from what is actually there
  /// rather than leaving playable audio invisible on disk forever.
  Future<int> recoverOrphans() async {
    await _load(force: true);
    final folder = await _folder();
    final known = {for (final e in _entries.values) e.fileName};
    var recovered = 0;

    await for (final item in folder.list()) {
      if (item is! File) continue;
      final name = item.path.split('/').last;
      if (name == _indexName || name.endsWith('.writing')) continue;
      if (known.contains(name)) continue;

      final isWav = name.endsWith('.wav');
      final isLc3 = name.endsWith('.lc3');
      if (!isWav && !isLc3) continue;

      final stat = await item.stat();
      final id = name.split('.').first;
      _entries[id] = Recording(
        id: id,
        fileName: name,
        capturedAt: stat.modified,
        duration: isWav
            ? Wav.durationOfPcm16(max(0, stat.size - 44))
            : Duration.zero,
        byteLength: stat.size,
        source: RecordingSource.glassesNote,
        format: isWav ? RecordingFormat.wav : RecordingFormat.lc3,
        transcriptError: 'Recovered from disk; the index had lost it.',
      );
      recovered++;
    }

    if (recovered > 0) {
      debugPrint('VoiceRecordings: recovered $recovered orphaned recording(s)');
      await _saveIndex();
      _emit();
    }
    return recovered;
  }

  /// Drops the oldest recordings once the folder grows past [maxBytesOnDisk].
  ///
  /// Announced in the log rather than done quietly: a recording disappearing
  /// is exactly the kind of thing that should never be a surprise.
  Future<void> _enforceCap() async {
    var total = _entries.values.fold<int>(0, (sum, e) => sum + e.byteLength);
    if (total <= maxBytesOnDisk) return;

    final oldestFirst = _entries.values.toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    for (final entry in oldestFirst) {
      if (total <= maxBytesOnDisk || _entries.length <= minKept) break;
      debugPrint(
        'VoiceRecordings: over the ${maxBytesOnDisk ~/ (1024 * 1024)}MB cap, '
        'dropping ${entry.fileName} from ${entry.capturedAt}',
      );
      _entries.remove(entry.id);
      total -= entry.byteLength;
      try {
        final file = await fileFor(entry);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('VoiceRecordings: could not delete ${entry.fileName}: $e');
      }
    }
    await _saveIndex();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @visibleForTesting
  void resetForTest() {
    _entries.clear();
    _seenAt = null;
    _loaded = false;
  }

  static final Random _random = Random();

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';
}
