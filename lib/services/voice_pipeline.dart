import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:g1_extended/services/dictation_service.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/services/voice_input_service.dart';
import 'package:g1_extended/services/wake_word_service.dart';

/// Wires the hands-free path together:
///
///   wake word heard -> record -> transcribe on device -> show and store
///
/// Each stage is a service that knows nothing about the others; this is the
/// only place that decides how they connect. The touchpad path in
/// [BluetoothReciever] is deliberately separate — it is triggered by hardware
/// and does not go through the wake word.
class VoicePipeline {
  VoicePipeline._internal();
  static final VoicePipeline singleton = VoicePipeline._internal();
  factory VoicePipeline() => singleton;

  final WakeWordService _wakeWord = WakeWordService.singleton;
  final VoiceInputService _input = VoiceInputService.singleton;

  StreamSubscription<VoiceInputState>? _inputSubscription;
  bool _started = false;

  /// How long to keep recording after the wake word before giving up.
  static const Duration _maxUtterance = Duration(seconds: 15);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _input.initialize();
    await _wakeWord.initialize();

    _wakeWord.setOnWakeWordDetected((confidence, source) {
      debugPrint('VoicePipeline: wake word from $source ($confidence)');
      unawaited(_capture());
    });

    _inputSubscription = _input.stateStream.listen(_onInputState);
  }

  Future<void> stop() async {
    _started = false;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _wakeWord.stopListening();
  }

  Future<void> _capture() async {
    final started = await _input.startRecording(maxDuration: _maxUtterance);
    if (!started) {
      debugPrint('VoicePipeline: could not start recording');
    }
  }

  Future<void> _onInputState(VoiceInputState state) async {
    if (state.status != VoiceInputStatus.complete) return;

    final audio = state.audioData;
    if (audio == null || audio.isEmpty) {
      debugPrint('VoicePipeline: capture produced no audio');
      return;
    }

    // The phone path already produced text through the platform recogniser;
    // only the glasses path hands us raw PCM that still needs transcribing.
    if (state.source != VoiceInputSource.glasses) return;

    try {
      final text =
          await SpeechRecognitionService.singleton.transcribeBytes(audio);
      await DictationService.singleton.record(text);
    } on SpeechModelMissingException catch (e) {
      debugPrint('VoicePipeline: $e');
    } catch (e) {
      debugPrint('VoicePipeline: transcription failed: $e');
    }
  }
}
