import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
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

  /// Emits download progress between 0.0 and 1.0.
  Stream<double> get downloadProgress => _progressController.stream;

  bool get isReady => _model != null;
  bool get isDownloading => _isDownloading;
  double get progress => _downloadProgress;

  VoskFlutterPlugin get plugin => _vosk;

  /// Returns the model path if it is already on disk, `null` otherwise.
  Future<String?> installedModelPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/vosk-models/$modelName');
    return await modelDir.exists() ? modelDir.path : null;
  }

  /// True when the model is on disk and does not need downloading.
  Future<bool> isModelInstalled() async => await installedModelPath() != null;

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

    try {
      _model = await _vosk.createModel(path);
      debugPrint('VoskModelManager: model loaded from $path');
      return _model;
    } catch (e) {
      debugPrint('VoskModelManager: failed to load model: $e');
      return null;
    }
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

      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      for (final entry in archive) {
        final target = '${modelsDir.path}/${entry.name}';
        if (entry.isFile) {
          await File(target).create(recursive: true);
          await File(target).writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(target).create(recursive: true);
        }
      }
      await zipFile.delete();

      _setProgress(1.0);
      return '${modelsDir.path}/$modelName';
    } catch (e) {
      debugPrint('VoskModelManager: download failed: $e');
      return null;
    } finally {
      client.close();
      _isDownloading = false;
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
