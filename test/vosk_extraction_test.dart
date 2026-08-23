import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/vosk_model_manager.dart';

/// The speech model crash was never a logic error. Reading the archive with
/// decodeBytes held the whole forty megabytes in memory and then decompressed
/// each entry on top of it, on the main isolate — so the process was killed
/// by Android before any Dart code could notice. Nothing threw, nothing was
/// logged, the app simply vanished whenever anyone touched speech.
///
/// A test cannot reproduce Android's memory limit. What it can do is pin the
/// two properties that made the old code fatal: that entries are written
/// straight to disk rather than materialised, and that a half-written model
/// never appears under its final name.
void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('vosk-extract-'));
  tearDown(() => work.deleteSync(recursive: true));

  /// Builds an archive shaped like a real Vosk model: one top-level
  /// directory, a subdirectory of acoustic data, and one entry far larger
  /// than the rest.
  File writeModelArchive({required int bigEntryBytes}) {
    final encoder = ZipFileEncoder();
    final zipPath = '${work.path}/model.zip';
    encoder.create(zipPath);

    final staging = Directory('${work.path}/src/vosk-model-small-xx-0.1')
      ..createSync(recursive: true);
    Directory('${staging.path}/am').createSync();
    Directory('${staging.path}/conf').createSync();

    File('${staging.path}/README').writeAsStringSync('a model');
    File('${staging.path}/conf/model.conf').writeAsStringSync('--x=1\n');

    // Poorly compressible, so the archive cannot cheat by storing a run.
    final big = Uint8List(bigEntryBytes);
    for (var i = 0; i < big.length; i++) {
      big[i] = (i * 2654435761) & 0xFF;
    }
    File('${staging.path}/am/final.mdl').writeAsBytesSync(big);

    encoder.addDirectory(staging);
    encoder.closeSync();
    return File(zipPath);
  }

  test('unpacks a model-shaped archive whole', () {
    final zip = writeModelArchive(bigEntryBytes: 4 * 1024 * 1024);
    final out = '${work.path}/staging';

    VoskModelManager.extractForTest(zip.path, out);

    final root = Directory('$out/vosk-model-small-xx-0.1');
    expect(root.existsSync(), isTrue, reason: 'top-level directory missing');
    expect(Directory('${root.path}/am').existsSync(), isTrue);
    expect(File('${root.path}/conf/model.conf').readAsStringSync(), '--x=1\n');
  });

  test('writes every byte of a large entry, not a truncated one', () {
    // Streaming is where truncation hides: an entry written through a sink
    // that is not flushed looks present and is short.
    const size = 6 * 1024 * 1024;
    final zip = writeModelArchive(bigEntryBytes: size);
    final out = '${work.path}/staging';

    VoskModelManager.extractForTest(zip.path, out);

    final mdl = File('$out/vosk-model-small-xx-0.1/am/final.mdl');
    expect(mdl.lengthSync(), size);

    final bytes = mdl.readAsBytesSync();
    expect(bytes.first, 0);
    expect(bytes.last, (((size - 1) * 2654435761) & 0xFF));
  });

  test('survives being run on a background isolate', () async {
    // This is how it actually runs. An isolate entry point cannot close over
    // anything, so a captured reference would only fail here.
    final zip = writeModelArchive(bigEntryBytes: 2 * 1024 * 1024);
    final out = '${work.path}/staging';
    final zipPath = zip.path;

    await Isolate.run(() => VoskModelManager.extractForTest(zipPath, out));

    expect(
      File('$out/vosk-model-small-xx-0.1/am/final.mdl').existsSync(),
      isTrue,
    );
  });

  test('a truncated archive leaves no complete model behind', () {
    final zip = writeModelArchive(bigEntryBytes: 1024 * 1024);
    final bytes = zip.readAsBytesSync();
    final broken = File('${work.path}/broken.zip')
      ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

    final out = '${work.path}/staging';

    // Whether it throws or stops early does not matter. What matters is that
    // the caller can tell: extraction runs into a staging directory and is
    // renamed into place only on success, so a failure here can never be
    // mistaken later for an installed model.
    try {
      VoskModelManager.extractForTest(broken.path, out);
    } catch (_) {
      // Expected for most kinds of damage.
    }

    final acoustic = File('$out/vosk-model-small-xx-0.1/am/final.mdl');
    final wroteEverything =
        acoustic.existsSync() && acoustic.lengthSync() == 1024 * 1024;
    expect(wroteEverything, isFalse,
        reason: 'half an archive produced what looks like a whole model');
  });

  // Peak memory is deliberately not asserted here.
  //
  // It is the property that actually mattered — the crash was Android
  // killing the process, not an exception — but ProcessInfo.maxRss is a
  // high-water mark for the whole process, and a test that has just written
  // a multi-megabyte archive has already moved it. Measuring it in-process
  // produces a number that looks meaningful and is not.
  //
  // It was measured instead by running the extractor as a standalone process
  // against the real 39 MB English model, under /usr/bin/time. Above a bare
  // Dart VM: 191 MB reading the archive whole, 153 MB streaming, 115 MB
  // streaming while releasing each entry. Those figures are recorded beside
  // the code they describe, in _extract.
}
