import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import 'package:g1_extended/services/vosk_model_manager.dart';

/// Service for wake word detection ("computer")
/// Uses Vosk for on-device, offline speech recognition
/// Apache 2.0 license - free for commercial use
class WakeWordService {
  static final WakeWordService singleton = WakeWordService._internal();
  factory WakeWordService() => singleton;
  WakeWordService._internal();

  // Vosk components
  final VoskModelManager _models = VoskModelManager.singleton;
  VoskFlutterPlugin get _vosk => _models.plugin;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  // Settings
  bool _isEnabled = false;
  String _wakeWord = 'computer';
  double _sensitivity = 0.5; // 0.0 to 1.0

  // State
  bool _isListening = false;
  bool _isInitialized = false;
  bool _isPaused = false;

  // Callbacks
  WakeWordCallback? _onWakeWordDetected;

  // Stream subscriptions
  StreamSubscription? _partialSubscription;
  StreamSubscription? _resultSubscription;

  // Stream controller for wake word events
  final StreamController<WakeWordEvent> _eventController =
      StreamController<WakeWordEvent>.broadcast();

  // Cooldown to prevent multiple detections
  DateTime? _lastDetection;
  static const _detectionCooldown = Duration(seconds: 2);

  // Minimum confidence threshold for wake word detection
  // Vosk confidence ranges from 0.0 to 1.0
  static const _minConfidenceThreshold = 0.75;

  // Recent audio energy tracking for noise rejection
  // ignore: unused_field
  final List<double> _recentEnergies = [];
  // ignore: unused_field
  static const _energyWindowSize = 10;
  // ignore: unused_field
  static const _minEnergyRatio = 2.0; // Audio must be 2x above ambient noise


  // Public getters
  bool get isEnabled => _isEnabled;
  bool get isListening => _isListening && !_isPaused;
  bool get isInitialized => _isInitialized;
  bool get isModelLoading => _models.isDownloading;
  double get modelDownloadProgress => _models.progress;
  String get wakeWord => _wakeWord;
  double get sensitivity => _sensitivity;
  Stream<WakeWordEvent> get eventStream => _eventController.stream;

  /// Initialize the wake word service
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('WakeWordService: Initializing with Vosk...');

    // Load settings from preferences
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('wake_word_enabled') ?? false;
    _wakeWord = prefs.getString('wake_word') ?? 'computer';
    _sensitivity = prefs.getDouble('wake_word_sensitivity') ?? 0.5;

    // Load the model if it is already on disk. If it is not, it gets
    // downloaded the first time the user enables the wake word.
    await _ensureModel();

    _isInitialized = true;
    debugPrint('WakeWordService: Initialized = $_isInitialized');

    // Auto-start if enabled
    if (_isEnabled && _model != null) {
      await startListening();
    }
  }

  /// Loads the shared offline model, downloading it if allowed.
  Future<bool> _ensureModel({bool allowDownload = false}) async {
    if (_model != null) return true;

    if (allowDownload && !await _models.isModelInstalled()) {
      _eventController.add(
        WakeWordEvent(type: WakeWordEventType.modelDownloadStarted),
      );
    }

    _model = await _models.load(allowDownload: allowDownload);

    if (_model == null) {
      _eventController.add(
        WakeWordEvent(
          type: WakeWordEventType.error,
          error: 'Speech model unavailable',
        ),
      );
      return false;
    }

    _eventController.add(
      WakeWordEvent(type: WakeWordEventType.modelDownloadComplete),
    );
    return true;
  }

  /// Create recognizer with grammar for wake word detection
  Future<bool> _createRecognizer() async {
    if (_model == null) return false;

    try {
      // Use grammar mode for efficient wake word detection
      // Only listen for specific words, much more efficient than full speech recognition
      // Include "[unk]" to allow Vosk to classify non-matching audio as unknown
      // This prevents random noise from being forced to match "computer"
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
        grammar: [
          _wakeWord,
          'hey computer',
          'okay computer',
          'hi computer',
          '[unk]', // Unknown token for noise/non-matching audio
        ],
      );
      debugPrint(
        'WakeWordService: Recognizer created with grammar: [$_wakeWord, [unk]]',
      );
      return true;
    } catch (e) {
      debugPrint('WakeWordService: Error creating recognizer: $e');
      return false;
    }
  }

  /// Handle partial recognition results
  void _handlePartialResult(String partial) {
    if (_isPaused) return;

    try {
      final json = jsonDecode(partial);
      final text = (json['partial'] as String?)?.toLowerCase() ?? '';

      // Don't trigger on partial results - too prone to false positives
      // We only log partials for debugging purposes
      if (text.isNotEmpty) {
        debugPrint(
            'WakeWordService: Partial: "$text" (not triggering on partial)');
      }
    } catch (e) {
      // Ignore JSON parse errors
    }
  }

  /// Handle final recognition results
  void _handleResult(String result) {
    if (_isPaused) return;

    try {
      final json = jsonDecode(result);
      final text = (json['text'] as String?)?.toLowerCase() ?? '';

      if (text.isEmpty) return;

      // Vosk returns confidence per word in the 'result' array
      // Format: {"result":[{"conf":0.9,"word":"computer","start":0.1,"end":0.5}],"text":"computer"}
      double maxConfidence = 0.0;
      bool wakeWordFound = false;

      final resultArray = json['result'] as List<dynamic>?;
      if (resultArray != null) {
        for (final wordInfo in resultArray) {
          final word = (wordInfo['word'] as String?)?.toLowerCase() ?? '';
          final conf = (wordInfo['conf'] as num?)?.toDouble() ?? 0.0;

          debugPrint('WakeWordService: Word: "$word" conf: $conf');

          // Check if this word matches our wake word
          if (word == _wakeWord.toLowerCase() ||
              word == 'hey' ||
              word == 'okay' ||
              word == 'hi') {
            if (word == _wakeWord.toLowerCase()) {
              wakeWordFound = true;
              maxConfidence = conf > maxConfidence ? conf : maxConfidence;
            }
          }
        }
      } else {
        // Fallback: no detailed result array, use text matching with lower confidence
        debugPrint('WakeWordService: No result array, text: "$text"');
        if (_containsWakeWord(text)) {
          wakeWordFound = true;
          maxConfidence = 0.5; // Lower confidence when no detailed info
        }
      }

      if (wakeWordFound) {
        debugPrint(
            'WakeWordService: Wake word found with confidence: $maxConfidence (threshold: $_minConfidenceThreshold)');
        if (maxConfidence >= _minConfidenceThreshold) {
          _triggerWakeWord(maxConfidence);
        } else {
          debugPrint('WakeWordService: Confidence too low, ignoring');
        }
      }
    } catch (e) {
      debugPrint('WakeWordService: Error parsing result: $e');
    }
  }

  /// Check if text contains the wake word
  bool _containsWakeWord(String text) {
    final words = text.toLowerCase().split(' ');
    return words.contains(_wakeWord.toLowerCase()) ||
        text.contains('hey $_wakeWord') ||
        text.contains('okay $_wakeWord') ||
        text.contains('hi $_wakeWord');
  }

  /// Trigger wake word detection
  void _triggerWakeWord(double confidence) {
    // Check cooldown to prevent multiple triggers
    final now = DateTime.now();
    if (_lastDetection != null &&
        now.difference(_lastDetection!) < _detectionCooldown) {
      debugPrint('WakeWordService: Cooldown active, ignoring detection');
      return;
    }
    _lastDetection = now;

    // Calculate effective threshold based on sensitivity setting
    // sensitivity 0.0 = very strict (threshold 0.95)
    // sensitivity 0.5 = default (threshold 0.75)
    // sensitivity 1.0 = lenient (threshold 0.55)
    final effectiveThreshold =
        _minConfidenceThreshold + ((1.0 - _sensitivity) * 0.2);

    if (confidence < effectiveThreshold) {
      debugPrint(
        'WakeWordService: Confidence $confidence below effective threshold $effectiveThreshold (sensitivity: $_sensitivity)',
      );
      return;
    }

    debugPrint(
        'WakeWordService: Wake word detected! confidence=$confidence, threshold=$effectiveThreshold');

    _eventController.add(
      WakeWordEvent(
        type: WakeWordEventType.detected,
        confidence: confidence,
        source: 'phone',
      ),
    );

    // Call the callback if set
    _onWakeWordDetected?.call(confidence, 'phone');
  }

  /// Set the callback for wake word detection
  void setOnWakeWordDetected(WakeWordCallback? callback) {
    _onWakeWordDetected = callback;
  }

  /// Enable or disable wake word detection
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_word_enabled', enabled);

    debugPrint('WakeWordService: Enabled set to $enabled');

    if (enabled) {
      // Downloads the shared model on first use.
      if (await _ensureModel(allowDownload: true)) {
        await startListening();
      } else {
        _eventController.add(
          WakeWordEvent(
            type: WakeWordEventType.error,
            error: 'Speech model not available. Please try again.',
          ),
        );
      }
    } else {
      await stopListening();
    }
  }

  /// Set the wake word (default: "computer")
  Future<void> setWakeWord(String wakeWord) async {
    _wakeWord = wakeWord.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wake_word', _wakeWord);

    debugPrint('WakeWordService: Wake word set to "$_wakeWord"');

    // Recreate recognizer with new grammar
    if (_isListening) {
      await stopListening();
      await startListening();
    }
  }

  /// Set the sensitivity (0.0 to 1.0, higher = more sensitive)
  Future<void> setSensitivity(double sensitivity) async {
    _sensitivity = sensitivity.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('wake_word_sensitivity', _sensitivity);

    debugPrint('WakeWordService: Sensitivity set to $_sensitivity');
  }

  /// Start listening for the wake word
  Future<bool> startListening() async {
    if (_model == null) {
      debugPrint('WakeWordService: Model not loaded');
      return false;
    }

    if (_isListening && !_isPaused) {
      debugPrint('WakeWordService: Already listening');
      return true;
    }

    try {
      // Create recognizer if needed
      if (_recognizer == null) {
        if (!await _createRecognizer()) {
          return false;
        }
      }

      // Initialize speech service
      _speechService = await _vosk.initSpeechService(_recognizer!);

      // Subscribe to results
      _partialSubscription = _speechService!.onPartial().listen(
            _handlePartialResult,
            onError: (e) => debugPrint('WakeWordService: Partial error: $e'),
          );

      _resultSubscription = _speechService!.onResult().listen(
            _handleResult,
            onError: (e) => debugPrint('WakeWordService: Result error: $e'),
          );

      // Start listening
      await _speechService!.start();
      _isListening = true;
      _isPaused = false;

      debugPrint('WakeWordService: Started listening for "$_wakeWord"');

      _eventController.add(
        WakeWordEvent(type: WakeWordEventType.listeningStarted),
      );

      return true;
    } catch (e) {
      debugPrint('WakeWordService: Error starting listening: $e');
      _eventController.add(
        WakeWordEvent(
          type: WakeWordEventType.error,
          error: 'Failed to start wake word detection: $e',
        ),
      );
      return false;
    }
  }

  /// Stop listening for the wake word
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _partialSubscription?.cancel();
      await _resultSubscription?.cancel();
      _partialSubscription = null;
      _resultSubscription = null;

      await _speechService?.stop();
      _speechService = null;

      // Keep recognizer for quick restart
      _isListening = false;
      _isPaused = false;

      debugPrint('WakeWordService: Stopped listening');

      _eventController.add(
        WakeWordEvent(type: WakeWordEventType.listeningStopped),
      );
    } catch (e) {
      debugPrint('WakeWordService: Error stopping listening: $e');
    }
  }

  /// Pause wake word detection temporarily (e.g., during voice recording)
  Future<void> pause() async {
    if (!_isListening || _isPaused) return;

    try {
      await _speechService?.stop();
      _isPaused = true;
      debugPrint('WakeWordService: Paused');
    } catch (e) {
      debugPrint('WakeWordService: Error pausing: $e');
    }
  }

  /// Resume wake word detection after pausing
  Future<void> resume() async {
    if (!_isEnabled || !_isListening || !_isPaused) return;

    try {
      await _speechService?.start();
      _isPaused = false;
      debugPrint('WakeWordService: Resumed');
    } catch (e) {
      debugPrint('WakeWordService: Error resuming: $e');
    }
  }

  /// Check if the device supports wake word detection.
  /// Vosk ships native libraries for Android, Linux and Windows.
  Future<bool> isSupported() async {
    return Platform.isAndroid || Platform.isLinux || Platform.isWindows;
  }

  /// Delete the downloaded model to free space.
  Future<void> deleteModel() async {
    await stopListening();
    _recognizer = null;
    _model = null;
    await _models.deleteModel();
  }

  /// Size of the installed model in bytes, 0 when it is not installed.
  Future<int> getModelSize() async {
    final path = await _models.installedModelPath();
    if (path == null) return 0;

    var size = 0;
    await for (final entity in Directory(path).list(recursive: true)) {
      if (entity is File) size += await entity.length();
    }
    return size;
  }

  /// Dispose of the service
  Future<void> dispose() async {
    await stopListening();
    _recognizer = null;
    _model = null;
    _eventController.close();
  }
}

/// Callback type for wake word detection
typedef WakeWordCallback = void Function(double confidence, String source);

/// Types of wake word events
enum WakeWordEventType {
  detected,
  listeningStarted,
  listeningStopped,
  modelDownloadStarted,
  modelDownloadProgress,
  modelDownloadComplete,
  error,
}

/// Wake word event
class WakeWordEvent {
  final WakeWordEventType type;
  final double? confidence;
  final String? source; // 'phone', 'glasses', 'watch'
  final String? error;
  final double? progress; // For download progress (0.0 to 1.0)

  WakeWordEvent({
    required this.type,
    this.confidence,
    this.source,
    this.error,
    this.progress,
  });
}
