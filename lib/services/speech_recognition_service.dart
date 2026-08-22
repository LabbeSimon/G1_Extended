import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vosk_flutter/vosk_flutter.dart' as vosk;

import 'package:g1_extended/services/vosk_model_manager.dart';

/// On-device speech recognition. No account, no API key, no network call.
///
/// Two paths, because the two microphones behave differently:
///
///  * [transcribeBytes] handles a finished PCM buffer — this is what the G1
///    microphone gives us after LC3 decoding. The platform recognisers only
///    accept a live microphone, so this path goes through Vosk.
///  * [listenOnPhone] handles the phone microphone in real time and uses the
///    platform recogniser, which is more accurate and needs no model download.
class SpeechRecognitionService {
  SpeechRecognitionService._internal();
  static final SpeechRecognitionService singleton =
      SpeechRecognitionService._internal();
  factory SpeechRecognitionService() => singleton;

  /// The G1 microphone streams 16 kHz mono PCM once LC3 has been decoded.
  static const int glassesSampleRate = 16000;

  final stt.SpeechToText _platformSpeech = stt.SpeechToText();
  bool _platformReady = false;

  /// Transcribes a raw PCM buffer captured from the glasses microphone.
  ///
  /// Expects 16-bit little-endian mono samples at [glassesSampleRate].
  /// Returns an empty string when nothing intelligible was recognised, and
  /// throws [SpeechModelMissingException] if the offline model is not present.
  Future<String> transcribeBytes(Uint8List pcm) async {
    final manager = VoskModelManager.singleton;
    final model = await manager.load(allowDownload: false);

    if (model == null) {
      throw SpeechModelMissingException();
    }

    vosk.Recognizer? recognizer;
    try {
      recognizer = await manager.plugin.createRecognizer(
        model: model,
        sampleRate: glassesSampleRate,
      );

      await recognizer.acceptWaveformBytes(pcm);
      final raw = await recognizer.getFinalResult();

      final text = (jsonDecode(raw) as Map<String, dynamic>)['text'] as String?;
      final result = text?.trim() ?? '';
      debugPrint(
        'SpeechRecognitionService: ${pcm.length} bytes -> "$result"',
      );
      return result;
    } catch (e) {
      debugPrint('SpeechRecognitionService: offline transcription failed: $e');
      rethrow;
    } finally {
      await recognizer?.dispose();
    }
  }

  /// Opens a streaming offline recognition session for live captions.
  ///
  /// Feed it PCM chunks as they arrive from the glasses; it emits the text
  /// recognised so far, refining as more audio comes in. Close the session
  /// when done so the native recogniser is released.
  Future<LiveTranscription> startLiveTranscription() async {
    final manager = VoskModelManager.singleton;
    final model = await manager.load(allowDownload: false);
    if (model == null) throw SpeechModelMissingException();

    final recognizer = await manager.plugin.createRecognizer(
      model: model,
      sampleRate: glassesSampleRate,
    );
    return LiveTranscription._(recognizer);
  }

  /// Listens on the phone microphone and returns what was said.
  ///
  /// Returns `null` if the platform recogniser is unavailable or heard nothing.
  Future<String?> listenOnPhone({
    Duration timeout = const Duration(seconds: 10),
    String localeId = 'fr_FR',
  }) async {
    if (!await _ensurePlatformReady()) return null;

    final completer = Completer<String?>();
    var recognised = '';

    await _platformSpeech.listen(
      onResult: (result) {
        recognised = result.recognizedWords;
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(recognised.isEmpty ? null : recognised);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: timeout,
        pauseFor: const Duration(seconds: 3),
        localeId: localeId,
        cancelOnError: true,
      ),
    );

    // Guard against the platform never delivering a final result.
    Timer(timeout + const Duration(seconds: 5), () async {
      if (!completer.isCompleted) {
        await _platformSpeech.stop();
        completer.complete(recognised.isEmpty ? null : recognised);
      }
    });

    return completer.future;
  }

  /// Stops an in-flight [listenOnPhone] session.
  Future<void> stopListening() async {
    if (_platformReady) await _platformSpeech.stop();
  }

  /// Locales the platform recogniser can handle, for the settings screen.
  Future<List<stt.LocaleName>> availableLocales() async {
    if (!await _ensurePlatformReady()) return const [];
    return _platformSpeech.locales();
  }

  Future<bool> _ensurePlatformReady() async {
    if (_platformReady) return true;
    _platformReady = await _platformSpeech.initialize(
      onError: (e) => debugPrint('SpeechRecognitionService: platform error $e'),
      onStatus: (s) => debugPrint('SpeechRecognitionService: platform $s'),
    );
    return _platformReady;
  }
}

/// Thrown when offline transcription is requested but the Vosk model has not
/// been downloaded yet. The caller should point the user at the voice settings.
class SpeechModelMissingException implements Exception {
  @override
  String toString() =>
      'The offline speech model is not installed. '
      'Download it from Settings > Voice.';
}

/// A running offline recognition session.
///
/// Vosk returns a final result when it detects a pause and a partial result
/// while speech is still flowing. Both are surfaced on [text] so the caller
/// can display a caption that updates as the sentence is spoken.
class LiveTranscription {
  LiveTranscription._(this._recognizer);

  final vosk.Recognizer _recognizer;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Text recognised so far, updated as audio is fed in.
  Stream<String> get text => _controller.stream;

  bool _closed = false;

  /// Feeds one chunk of 16 kHz mono PCM16 audio.
  Future<void> feed(Uint8List pcm) async {
    if (_closed || pcm.isEmpty) return;

    try {
      final endOfSentence = await _recognizer.acceptWaveformBytes(pcm);
      final raw = endOfSentence
          ? await _recognizer.getResult()
          : await _recognizer.getPartialResult();

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final value =
          (endOfSentence ? decoded['text'] : decoded['partial']) as String?;
      final trimmed = value?.trim() ?? '';

      if (trimmed.isNotEmpty && !_controller.isClosed) {
        _controller.add(trimmed);
      }
    } catch (e) {
      debugPrint('LiveTranscription: chunk dropped: $e');
    }
  }

  /// Ends the session and releases the native recogniser.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _recognizer.dispose();
    await _controller.close();
  }
}
