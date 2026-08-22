import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Owns the offline Vosk speech model.
///
/// The model is downloaded once, stored in the app documents directory and
/// shared by every consumer (wake word detection and transcription), so the
/// ~50 MB of acoustic data is only ever held in memory a single time.
///
/// Nothing here talks to a server beyond the one-off model download from
/// alphacephei.com. Audio never leaves the device.
class VoskModelManager {
  VoskModelManager._internal();
  static final VoskModelManager singleton = VoskModelManager._internal();
  factory VoskModelManager() => singleton;

  static const modelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip';
  static const modelName = 'vosk-model-small-en-us-0.15';

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();

  Model? _model;
  Future<Model?>? _pending;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  /// Set on disk before handing a model to the native loader, cleared once it
  /// comes back.
  ///
  /// Loading happens in native code: if it dies there, no Dart catch runs and
  /// nothing records what happened. The app then reopens, loads the same
  /// model, and dies again — a loop the user cannot break without clearing
  /// the app's data. A marker that survives the crash is the only way to
  /// notice on the next launch that this exact model killed us last time.
  static const String _loadAttemptMarker = 'load-in-progress';

  /// True when the previous attempt to load the model did not return.
  bool suspectedBadModel = false;

  /// Emits download progress between 0.0 and 1.0.
  Stream<double> get downloadProgress => _progressController.stream;

  bool get isReady => _model != null;
  bool get isDownloading => _isDownloading;
  double get progress => _downloadProgress;

  VoskFlutterPlugin get plugin => _vosk;

  /// Marks an extraction in progress. A directory under this name is never
  /// handed to the native loader.
  static const String _stagingPrefix = '.incomplete-';

  /// Returns the model path if a *complete* model is on disk.
  ///
  /// Completeness matters more than it sounds. A half-extracted model looks
  /// installed, and handing it to the native loader crashes the process
  /// rather than throwing — so one interrupted download would poison every
  /// launch afterwards, with no way for Dart to catch it. Extraction
  /// therefore happens under a staging name and is renamed into place only
  /// once finished, which makes the final directory's existence proof that
  /// it is whole.
  Future<String?> installedModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/vosk-models/$modelName');
    if (!await modelDir.exists()) return null;

    // A model missing its acoustic data is not a model.
    if (!await Directory('${modelDir.path}/am').exists()) {
      debugPrint('VoskModelManager: incomplete model on disk, removing it');
      await modelDir.delete(recursive: true);
      return null;
    }

    return modelDir.path;
  }

  /// Clears anything a previous run left half-written.
  Future<void> _clearStaging(Directory modelsDir) async {
    if (!await modelsDir.exists()) return;

    await for (final entry in modelsDir.list()) {
      final name = entry.path.split('/').last;
      if (name.startsWith(_stagingPrefix) || name.endsWith('.zip')) {
        debugPrint('VoskModelManager: clearing leftover $name');
        await entry.delete(recursive: true);
      }
    }
  }

  /// True when the model is on disk and does not need downloading.
  Future<bool> isModelInstalled() async => await installedModelPath() != null;

  /// Fetches and unpacks the model without handing it to the native loader.
  ///
  /// Downloading and loading used to be the same call, which meant the
  /// download button ended by asking native code to parse 50 MB — and if that
  /// dies, it takes the process with it and no Dart catch runs. Someone
  /// tapping "download" would simply watch the app vanish. Separating them
  /// means the download can only ever fail politely; loading happens later,
  /// when speech is actually used, where a failure is recoverable.
  ///
  /// Returns true when a complete model is on disk afterwards.
  Future<bool> ensureDownloaded() async {
    if (await isModelInstalled()) return true;
    return await _download() != null;
  }

  /// Loads the model, downloading it first if [allowDownload] is set.
  ///
  /// Concurrent calls share a single load: callers never race to download the
  /// same archive twice.
  Future<Model?> load({bool allowDownload = true}) {
    if (_model != null) return Future.value(_model);
    return _pending ??= _load(allowDownload).whenComplete(() {
      _pending = null;
    });
  }

  Future<Model?> _load(bool allowDownload) async {
    var path = await installedModelPath();

    if (path == null) {
      if (!allowDownload) return null;
      path = await _download();
      if (path == null) return null;
    }

    final marker = File('$path/$_loadAttemptMarker');

    if (await marker.exists()) {
      // Last time we got this far, the process did not come back.
      debugPrint('VoskModelManager: previous load never returned, refusing');
      suspectedBadModel = true;
      return null;
    }

    try {
      await marker.create(recursive: true);
      _model = await _vosk.createModel(path);
      debugPrint('VoskModelManager: model loaded from $path');
      return _model;
    } catch (e) {
      debugPrint('VoskModelManager: failed to load model: $e');
      return null;
    } finally {
      if (await marker.exists()) await marker.delete();
    }
  }

  /// Throws away a model that has been refusing to load.
  Future<void> discardSuspectModel() async {
    suspectedBadModel = false;
    await deleteModel();
  }

  Future<String?> _download() async {
    if (_isDownloading) return null;
    _isDownloading = true;
    _setProgress(0.0);

    final client = http.Client();
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/vosk-models');
      await modelsDir.create(recursive: true);
      await _clearStaging(modelsDir);

      final response = await client.send(http.Request('GET', Uri.parse(modelUrl)));
      if (response.statusCode != 200) {
        throw HttpException('model download returned ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      final zipFile = File('${modelsDir.path}/$modelName.zip');
      final sink = zipFile.openWrite();
      var received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) _setProgress(received / total);
      }
      await sink.close();

      // Extraction runs on its own isolate, streamed entry by entry, into a
      // staging directory.
      //
      // Reading the archive with decodeBytes held the whole 40 MB zip in
      // memory and then decompressed each entry on top of it, on the main
      // isolate. The model contains single files of tens of megabytes, so
      // peak usage went far past what Android grants an app: the process was
      // killed, which looked from the outside like the app crashing whenever
      // anyone touched speech recognition.
      final staging = Directory('${modelsDir.path}/$_stagingPrefix$modelName');
      final zipPath = zipFile.path;
      final stagingPath = staging.path;

      try {
        await Isolate.run(() => _extract(zipPath, stagingPath));
        await zipFile.delete();

        // The archive contains a single top-level directory named after the
        // model; the staging directory therefore holds it one level down.
        final extracted = Directory('$stagingPath/$modelName');
        final source = await extracted.exists() ? extracted : staging;

        final destination = Directory('${modelsDir.path}/$modelName');
        if (await destination.exists()) {
          await destination.delete(recursive: true);
        }

        // Rename is what makes this safe: the final directory appears whole
        // or not at all.
        await source.rename(destination.path);
        if (await staging.exists()) await staging.delete(recursive: true);

        _setProgress(1.0);
        return destination.path;
      } catch (e) {
        debugPrint('VoskModelManager: extraction failed: $e');
        if (await staging.exists()) await staging.delete(recursive: true);
        if (await zipFile.exists()) await zipFile.delete();
        return null;
      }
    } catch (e) {
      debugPrint('VoskModelManager: download failed: $e');
      return null;
    } finally {
      client.close();
      _isDownloading = false;
    }
  }

  /// Unpacks the archive without ever holding it whole.
  ///
  /// Runs on a background isolate, so it neither blocks the interface nor
  /// counts against the main isolate's heap. Static because an isolate entry
  /// point cannot close over `this`.
  static void _extract(String zipPath, String destination) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);

      for (final entry in archive) {
        final target = '$destination/${entry.name}';

        if (!entry.isFile) {
          Directory(target).createSync(recursive: true);
          continue;
        }

        Directory(File(target).parent.path).createSync(recursive: true);
        final output = OutputFileStream(target);
        try {
          // Streams the entry straight to disk rather than materialising it.
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
    } finally {
      input.closeSync();
    }
  }

  /// Removes the downloaded model from disk and frees it from memory.
  Future<void> deleteModel() async {
    _model = null;
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/vosk-models/$modelName');
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }

  void _setProgress(double value) {
    _downloadProgress = value;
    if (!_progressController.isClosed) _progressController.add(value);
  }
}
