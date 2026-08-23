import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vosk_flutter/vosk_flutter.dart';

import 'package:g1_extended/models/speech_model.dart';
import 'package:g1_extended/services/memory_state.dart';
import 'package:g1_extended/services/vosk_model_manager.dart';
import 'package:g1_extended/services/wake_word_vocabulary.dart';

/// Listens for a spoken wake word, entirely on the device.
///
/// The word must be one the installed model's lexicon contains. Vosk cannot
/// return a word it does not know — not with poor confidence, not at all — so
/// a wake word from the wrong language leaves a feature that appears to be
/// running and can never fire. [WakeWordVocabulary] is what keeps the choice
/// honest.
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
    // The default follows the installed model, because a wake word absent
    // from that model's lexicon can never be returned by it — the feature
    // would look configured and simply never fire.
    final model = await VoskModelManager.singleton.loadSelection();
    _wakeWord =
        prefs.getString('wake_word') ?? WakeWordVocabulary.defaultFor(model);
    _sensitivity = prefs.getDouble('wake_word_sensitivity') ?? 0.5;

    // Deliberately not loaded here.
    //
    // Handing a 50 MB model to a native loader during start-up means that any
    // failure in that loader takes the whole app down before it draws
    // anything, on every launch, with no way for the user to get back in and
    // turn the feature off. It is loaded when the wake word is switched on,
    // where a failure is recoverable and visible.

    _isInitialized = true;
    debugPrint('WakeWordService: Initialized = $_isInitialized');

    // Auto-start if enabled
    if (_isEnabled && _model != null) {
      await startListening();
    }
  }

  /// The model id [_model] was loaded from, and the word the current
  /// recognizer's grammar was built with.
  ///
  /// These exist because both were once assumed instead of checked. The
  /// recognizer was kept across stop/start "for a quick restart", so setting
  /// a new wake word rebuilt nothing: the grammar still said "computer", the
  /// new word was classified as [unk] forever, and no error said so anywhere.
  /// Switching language had the same shape one level up — the service kept
  /// its cached English model after the French one was selected, and
  /// "souffleur" is not a word the English lexicon can ever produce.
  String? _armedModelId;
  String? _armedWord;

  /// What is actually armed right now, for the settings screen to show.
  ///
  /// Null when not listening. The point is to make the silent failure
  /// impossible: if this says « souffleur · Français », that is what the
  /// recognizer was genuinely built with, not what the preferences wish.
  String? get armedDescription {
    if (!_isListening || _armedWord == null) return null;
    final model = SpeechModel.byId(_armedModelId ?? '');
    return '$_armedWord · ${model.languageLabel}';
  }

  /// Loads the shared offline model, downloading it if allowed.
  Future<bool> _ensureModel({bool allowDownload = false}) async {
    // A cached model is only a shortcut while it is still the selected one.
    if (_model != null && _armedModelId != _models.model.id) {
      debugPrint('WakeWordService: model changed '
          '($_armedModelId -> ${_models.model.id}), dropping the old one');
      _recognizer = null;
      _model = null;
    }
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

    _armedModelId = _models.model.id;
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
        // The grammar is built from the configured word rather than a fixed
        // list. It used to name "computer" explicitly, so changing the wake
        // word left the recogniser still listening for the old one alongside
        // the new.
        //
        // "[unk]" is what keeps this honest: without it Vosk must map every
        // sound it hears onto some word in the grammar, and a closed grammar
        // of one word turns any cough into a detection.
        grammar: [
          _wakeWord,
          for (final prefix in _prefixes) '$prefix $_wakeWord',
          '[unk]',
        ],
      );
      _armedWord = _wakeWord;
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
          if (word == _wakeWord.toLowerCase()) {
            wakeWordFound = true;
            maxConfidence = conf > maxConfidence ? conf : maxConfidence;
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
    if (words.contains(_wakeWord.toLowerCase())) return true;
    return _prefixes.any((p) => text.contains('$p $_wakeWord'));
  }

  /// Openings people put in front of a wake word without thinking about it.
  ///
  /// Both languages, unconditionally: someone who has set a French wake word
  /// may well still say "hey" in front of it.
  static const List<String> _prefixes = ['hey', 'okay', 'hi', 'eh', 'dis'];

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

  /// Resumes listening after a restart, if it was left on.
  ///
  /// initialize() reads the preferences and deliberately does not load the
  /// model — but nothing else did either, so the switch came back showing
  /// "on" over a service that had stopped listening the moment the app was
  /// closed. Enabled and deaf, with nothing to say why.
  ///
  /// Three refusals, all of them better than the alternative:
  ///
  /// The model is never downloaded from here. Forty megabytes pulled down
  /// unasked at launch is not something to do on someone's data.
  ///
  /// Nor is it loaded when memory is short. The loader is native and takes
  /// the process with it when there is no room, and app start-up is the
  /// worst possible moment for that — it would look like an app that
  /// refuses to open at all.
  ///
  /// Nor when the previous load never returned. That marker exists exactly
  /// so a bad model kills the app once rather than every time.
  Future<void> resumeIfEnabled() async {
    if (!_isEnabled) return;

    final models = VoskModelManager.singleton;
    if (!await models.isModelInstalled()) {
      debugPrint('WakeWordService: enabled, but no model on the device');
      _eventController.add(WakeWordEvent(
        type: WakeWordEventType.error,
        error: 'The speech model is not downloaded, so the wake word cannot '
            'listen. Open Voice settings to fetch it.',
      ));
      return;
    }

    if (models.suspectedBadModel) {
      debugPrint('WakeWordService: refusing a model that killed us before');
      return;
    }

    final memory = await MemoryState.read();
    if (memory != null && memory.speechModelIsRisky) {
      debugPrint('WakeWordService: too little memory to load at start-up');
      _eventController.add(WakeWordEvent(
        type: WakeWordEventType.error,
        error: 'Not enough free memory to start the wake word right now.',
      ));
      return;
    }

    debugPrint('WakeWordService: resuming after restart');
    if (await _ensureModel(allowDownload: false)) {
      await startListening();
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
      // Rebuild whenever the recognizer no longer matches the configured
      // word — not merely when it is missing. Keeping it across a word
      // change is precisely how "souffleur" ended up spoken at a grammar
      // that still said "computer".
      if (_recognizer == null || _armedWord != _wakeWord) {
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
      // Disposed, not merely stopped and dropped. The platform side keeps a
      // single microphone service alive; abandoning it while holding no
      // reference means the next initSpeechService finds it already taken
      // and the second enable of the toggle fails where the first worked.
      await _speechService?.dispose();
      _speechService = null;

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
