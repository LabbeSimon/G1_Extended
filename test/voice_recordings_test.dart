import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/services/voice_recordings.dart';
import 'package:g1_extended/utils/wav.dart';

/// The audio reaching disk is the one thing in this area that must never
/// depend on anything else working. These guard that: a recording survives
/// a missing speech model, a failed decode, a lost index, and a second
/// isolate — because every one of those used to destroy it silently.
void main() {
  late Directory dir;
  final store = VoiceRecordings.singleton;

  Uint8List pcm(int samples) => Uint8List(samples * 2);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('recordings-');
    VoiceRecordings.directoryForTest = dir;
    store.resetForTest();
  });

  tearDown(() {
    VoiceRecordings.directoryForTest = null;
    store.resetForTest();
    dir.deleteSync(recursive: true);
  });

  group('Keeping the audio', () {
    test('a saved recording is a real file with real bytes in it', () async {
      final recording = await store.savePcm(
        pcm(16000),
        source: RecordingSource.glassesNote,
      );

      final file = await store.fileFor(recording);
      expect(await file.exists(), isTrue);
      expect(await file.length(), 44 + 32000);
      expect(recording.byteLength, 44 + 32000);
    });

    test('the file it writes is a playable WAV, not headerless bytes', () async {
      final recording = await store.savePcm(
        pcm(800),
        source: RecordingSource.glassesLive,
      );

      final bytes = await (await store.fileFor(recording)).readAsBytes();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(recording.isPlayable, isTrue);
    });

    test('it knows how long the recording lasts', () async {
      final recording = await store.savePcm(
        pcm(16000),
        source: RecordingSource.glassesNote,
      );
      expect(recording.duration, const Duration(seconds: 1));
    });

    test('an empty capture is refused rather than stored as a stub', () async {
      expect(
        () => store.savePcm(Uint8List(0), source: RecordingSource.phone),
        throwsArgumentError,
      );
    });

    test('nothing half-written is left behind on success', () async {
      await store.savePcm(pcm(100), source: RecordingSource.phone);
      final leftovers = dir
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.writing'));
      expect(leftovers, isEmpty);
    });
  });

  group('When the recogniser fails', () {
    test('audio that was never transcribed is still listed', () async {
      await store.savePcm(pcm(400), source: RecordingSource.glassesNote);

      final all = await store.all();
      expect(all, hasLength(1));
      expect(all.single.hasTranscript, isFalse);
      expect(await (await store.fileFor(all.single)).exists(), isTrue);
    });

    test('the reason is recorded next to the audio, not instead of it',
        () async {
      final recording =
          await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      await store.attachTranscriptError(recording.id, 'No speech model');

      final stored = await store.byId(recording.id);
      expect(stored!.transcriptError, 'No speech model');
      expect(await (await store.fileFor(stored)).exists(), isTrue);
    });

    test('a transcript arriving later clears the earlier complaint', () async {
      final recording =
          await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      await store.attachTranscriptError(recording.id, 'No speech model');
      await store.attachTranscript(recording.id, 'call the plumber');

      final stored = await store.byId(recording.id);
      expect(stored!.transcript, 'call the plumber');
      expect(stored.transcriptError, isNull);
    });

    test('undecodable audio is kept as raw codec bytes, not discarded',
        () async {
      final codec = Uint8List.fromList(List.filled(200, 0x5a));
      final recording = await store.saveUndecodedLc3(
        codec,
        source: RecordingSource.glassesNote,
      );

      expect(recording.format, RecordingFormat.lc3);
      expect(recording.isPlayable, isFalse);
      expect(recording.transcriptError, isNotNull);
      expect(await (await store.fileFor(recording)).readAsBytes(), codec);
    });
  });

  group('Across isolates', () {
    test('a recording saved by the service is seen by the interface',
        () async {
      await store.savePcm(pcm(400), source: RecordingSource.glassesNote);

      // A second isolate: same files, no shared memory.
      store.resetForTest();
      expect(await store.all(), hasLength(1));
    });

    test('a transcript attached elsewhere is picked up on next read', () async {
      final recording =
          await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      await store.attachTranscript(recording.id, 'heard this');

      store.resetForTest();
      final stored = await store.byId(recording.id);
      expect(stored!.transcript, 'heard this');
    });
  });

  group('When the index is lost', () {
    test('playable audio on disk is put back in the list', () async {
      final recording =
          await store.savePcm(pcm(16000), source: RecordingSource.glassesNote);

      // The index is only a description of the files; destroy it.
      File('${dir.path}/voice_recordings/index.json').deleteSync();
      store.resetForTest();
      expect(await store.all(), isEmpty);

      final recovered = await store.recoverOrphans();
      expect(recovered, 1);

      final all = await store.all();
      expect(all, hasLength(1));
      expect(all.single.fileName, recording.fileName);
      expect(all.single.duration, const Duration(seconds: 1));
    });

    test('a corrupt index does not take the audio down with it', () async {
      await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      File('${dir.path}/voice_recordings/index.json')
          .writeAsStringSync('{ not json at all');

      store.resetForTest();
      expect(await store.all(), isEmpty);
      expect(await store.recoverOrphans(), 1);
    });

    test('recovery does not duplicate what the index already knows', () async {
      await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      expect(await store.recoverOrphans(), 0);
      expect(await store.all(), hasLength(1));
    });

    test('the index file itself is never mistaken for a recording', () async {
      await store.savePcm(pcm(400), source: RecordingSource.glassesNote);
      store.resetForTest();
      await store.recoverOrphans();

      final names = (await store.all()).map((e) => e.fileName);
      expect(names, isNot(contains('index.json')));
    });
  });

  group('Removing', () {
    test('deleting a recording deletes its file too', () async {
      final recording =
          await store.savePcm(pcm(400), source: RecordingSource.phone);
      final file = await store.fileFor(recording);

      await store.remove(recording.id);
      expect(await file.exists(), isFalse);
      expect(await store.all(), isEmpty);
    });

    test('an unknown id is ignored rather than throwing', () async {
      await store.savePcm(pcm(400), source: RecordingSource.phone);
      await store.remove('nothing-like-this');
      expect(await store.all(), hasLength(1));
    });
  });

  group('Ordering and accounting', () {
    test('newest first, so the last thing said is the first thing shown',
        () async {
      final older = await store.savePcm(
        pcm(100),
        source: RecordingSource.glassesNote,
        capturedAt: DateTime(2026, 1, 1),
      );
      final newer = await store.savePcm(
        pcm(100),
        source: RecordingSource.glassesNote,
        capturedAt: DateTime(2026, 6, 1),
      );

      final all = await store.all();
      expect(all.first.id, newer.id);
      expect(all.last.id, older.id);
    });

    test('it can say how much room the recordings take', () async {
      await store.savePcm(pcm(100), source: RecordingSource.phone);
      await store.savePcm(pcm(100), source: RecordingSource.phone);
      expect(await store.totalBytes(), 2 * (44 + 200));
    });

    test('the source each recording came from survives a reload', () async {
      await store.savePcm(pcm(100), source: RecordingSource.glassesLive);
      store.resetForTest();
      expect((await store.all()).single.source, RecordingSource.glassesLive);
    });
  });

  group('Announcing changes', () {
    test('saving tells the interface something appeared', () async {
      final seen = <void>[];
      final sub = store.changes.listen(seen.add);
      await store.savePcm(pcm(100), source: RecordingSource.phone);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, isNotEmpty);
    });
  });

  group('The index on disk', () {
    test('is written as readable JSON another isolate can parse', () async {
      await store.savePcm(pcm(100), source: RecordingSource.glassesNote);
      final raw =
          File('${dir.path}/voice_recordings/index.json').readAsStringSync();
      final decoded = jsonDecode(raw) as Map;
      expect(decoded['recordings'], hasLength(1));
      expect((decoded['recordings'] as List).single['format'], 'wav');
    });
  });
}
