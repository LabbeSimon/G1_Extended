import 'dart:async';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/case_battery.dart';
import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/dictation_service.dart';
import 'package:g1_extended/services/notification_history.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/utils/lc3.dart';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added import
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Command response status codes
const int RESPONSE_SUCCESS = 0xC9;
const int RESPONSE_FAILURE = 0xCA;

class BluetoothReciever {
  static final BluetoothReciever singleton = BluetoothReciever._internal();

  final voiceCollector = VoiceDataCollector();

  // Speech to text setup
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';
  // ---

  factory BluetoothReciever() {
    return singleton;
  }

  BluetoothReciever._internal() {
    _initSpeech(); // Initialize speech recognition
  }

  /// This has to happen only once per app. Returns true if successful.
  Future<bool> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) => debugPrint('Speech recognition error: $error'),
        onStatus: _onSpeechStatus,
      );
      debugPrint("Speech recognition initialized: $_speechEnabled");
    } catch (e) {
      debugPrint("Error initializing speech recognition: $e");
      _speechEnabled = false;
    }
    return _speechEnabled;
  }

  /// Each time to start a speech recognition session
  void _startListening() async {
    if (!_speechEnabled) {
      debugPrint('Speech recognition not enabled');
      return;
    }
    if (_isListening) {
      debugPrint('Already listening');
      return;
    }
    debugPrint('Starting speech recognition listener');
    _lastWords = '';
    // TODO: Consider locale from settings? speech_to_text uses system default
    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
      ),
    );
    _isListening = true; // Set listening status based on callback?
  }

  /// Stop the recognition session
  void _stopListening() async {
    if (!_isListening) {
      debugPrint('Not currently listening');
      return;
    }
    debugPrint('Stopping speech recognition listener');
    await _speechToText.stop();
    _isListening = false; // Set listening status based on callback?
  }

  /// This is the callback that the SpeechToText plugin calls when
  /// the platform returns recognition results.
  void _onSpeechResult(SpeechRecognitionResult result) async {
    _lastWords = result.recognizedWords;
    debugPrint('Speech Result: $_lastWords, Final: ${result.finalResult}');

    if (result.finalResult) {
      _isListening = false; // Recognition finished
      if (_lastWords.isNotEmpty) {
        debugPrint('Final transcription: $_lastWords');
        await DictationService.singleton.record(
          _lastWords,
          source: DictationSource.phone,
        );
      } else {
        debugPrint('Final transcription is empty.');
      }
    }
  }

  /// Handle status changes from the speech recognition engine
  void _onSpeechStatus(String status) {
    debugPrint('Speech Recognition Status: $status');
    // Update _isListening based on status if needed, e.g., 'listening', 'notListening', 'done'
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
    } else if (status == 'listening') {
      _isListening = true;
    }
  }

  /// Which microphone the touchpad dictates through.
  ///
  /// The phone microphone uses the platform recogniser: more accurate, no
  /// model to download. The glasses microphone is hands-free but goes through
  /// the offline Vosk model. Both stay on the device.
  Future<bool> _useGlassesMicrophone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('use_glasses_microphone') ?? false;
  }

  /// Requests waiting for a reply, keyed by the command byte they sent.
  ///
  /// The G1 echoes the command id back in the first byte of its response, so
  /// that byte is enough to match a reply to the request that asked for it.
  final Map<int, Completer<List<int>>> _pendingReplies = {};

  /// Registers interest in the next response carrying [command].
  ///
  /// Returns null if nothing arrives within [timeout], rather than hanging:
  /// the glasses silently ignore commands they do not understand.
  Future<List<int>?> awaitReply(
    int command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // A second request for the same command supersedes the first.
    _pendingReplies.remove(command)?.complete(const []);

    final completer = Completer<List<int>>();
    _pendingReplies[command] = completer;

    try {
      final reply = await completer.future.timeout(timeout);
      return reply.isEmpty ? null : reply;
    } on TimeoutException {
      debugPrint('No reply to command 0x${command.toRadixString(16)}');
      return null;
    } finally {
      _pendingReplies.remove(command);
    }
  }

  /// Hands [data] to a waiting request, if one asked for this command.
  /// Returns true when the packet was consumed by a pending request.
  bool _deliverToPendingReply(List<int> data) {
    final completer = _pendingReplies[data[0]];
    if (completer == null || completer.isCompleted) return false;
    completer.complete(List<int>.unmodifiable(data));
    return true;
  }

  Future<void> receiveHandler(GlassSide side, List<int> data) async {
    if (data.isEmpty) return;

    // Settings replies are consumed by whoever asked for them.
    if (_deliverToPendingReply(data)) return;

    int command = data[0];

    switch (command) {
      case Commands.HEARTBEAT:
        break;
      case Commands.START_AI:
        // 0xF5 carries both the touchpad events and spontaneous state
        // changes. handleEvenAICommand only receives the subcommand, so
        // anything with a payload has to be read before dispatching or the
        // payload is simply dropped.
        final caseBattery = CaseBatteryParser.fromStateChange(data);
        if (caseBattery != null) {
          BluetoothManager.singleton.updateCaseBattery(caseBattery);
          break;
        }

        if (data.length >= 2) {
          handleEvenAICommand(side, data[1]);
        }
        break;

      case Commands.MIC_RESPONSE: // Mic Response
        if (data.length >= 3) {
          int status = data[1];
          int enable = data[2];
          handleMicResponse(side, status, enable);
        }
        break;

      case Commands.RECEIVE_MIC_DATA: // Voice Data
        if (data.length >= 2) {
          int seq = data[1];
          List<int> voiceData = data.sublist(2);
          handleVoiceData(side, seq, voiceData);
        }
        break;
      case Commands.GET_BATTERY: // Battery Response
        // Battery responses are handled directly in the Glass class
        // This case is here for completeness and potential future use
        debugPrint(
          '[$side] Battery response received in receiver: ${data.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}',
        );
        break;
      case Commands.QUICK_NOTE:
        handleQuickNoteCommand(side, data);
        break;
      case Commands.QUICK_NOTE_ADD:
        handleQuickNoteAudioData(side, data);
        break;

      default:
        debugPrint('[$side] Unknown command: 0x${command.toRadixString(16)}');
    }
  }

  /// True while a touchpad-initiated capture is running.
  bool _isCapturing = false;

  /// Puts a recent notification back on the lens.
  ///
  /// Repeated taps walk further back, which is why the history keeps a
  /// cursor rather than only the newest.
  Future<void> _recallNotification() async {
    final recalled = NotificationHistory.singleton.recallNext();
    final bt = BluetoothManager();

    try {
      await bt.sendPriorityText(
        recalled?.forGlasses() ?? 'Nothing recent',
      );
    } catch (e) {
      debugPrint('Could not recall a notification: $e');
    }
  }

  /// Start capturing speech after a touchpad press.
  Future<void> _beginDictation(GlassSide side) async {
    if (_isCapturing) {
      debugPrint('[$side] Capture already running');
      return;
    }
    _isCapturing = true;

    final bt = BluetoothManager();

    if (await _useGlassesMicrophone()) {
      debugPrint('[$side] Capturing through the glasses microphone');
      voiceCollector.reset();
      voiceCollector.isRecording = true;
    } else {
      debugPrint('[$side] Capturing through the phone microphone');
      if (!_speechEnabled) await _initSpeech();
      if (_speechEnabled) {
        _startListening();
      } else {
        debugPrint('[$side] Platform recogniser unavailable, capture aborted');
        _isCapturing = false;
        return;
      }
    }

    // The glasses need the mic opened either way: it drives the on-screen
    // recording indicator the wearer sees.
    await bt.setMicrophone(true);
  }

  /// Stop capturing, transcribe what was said and hand it to the dictation log.
  Future<void> _finishDictation(GlassSide side) async {
    if (!_isCapturing) {
      debugPrint('[$side] No capture in progress');
      return;
    }
    _isCapturing = false;

    final bt = BluetoothManager();

    if (!await _useGlassesMicrophone()) {
      // The platform recogniser reports its own result through _onSpeechResult.
      _stopListening();
      await bt.setMicrophone(false);
      return;
    }

    voiceCollector.isRecording = false;
    await bt.setMicrophone(false);

    final encoded = await voiceCollector.getAllDataAndReset();
    if (encoded.isEmpty) {
      debugPrint('[$side] No audio captured');
      return;
    }

    final pcm = await LC3.decodeLC3(Uint8List.fromList(encoded));
    if (pcm.isEmpty) {
      debugPrint('[$side] LC3 decoding produced no samples');
      return;
    }

    final startedAt = DateTime.now();
    try {
      final transcript =
          await SpeechRecognitionService.singleton.transcribeBytes(pcm);
      final elapsed = DateTime.now().difference(startedAt);
      debugPrint(
        '[$side] Transcribed ${pcm.length} bytes in ${elapsed.inMilliseconds}ms: "$transcript"',
      );
      await DictationService.singleton.record(transcript);
    } on SpeechModelMissingException {
      debugPrint('[$side] Offline speech model missing');
      await bt.sendPriorityText(
        'Speech model not installed.\nSettings > Voice to download it.',
      );
    } catch (e) {
      debugPrint('[$side] Transcription failed: $e');
    }
  }

  void handleEvenAICommand(GlassSide side, int subcmd) async {
    final bt = BluetoothManager();
    switch (subcmd) {
      case 0:
        debugPrint('[$side] Exit to dashboard manually');
        await bt.setMicrophone(false);
        voiceCollector.isRecording = false;
        voiceCollector.reset();
        break;
      case 1:
        debugPrint(
          '[$side] Page ${side == GlassSide.left ? 'up' : 'down'} control',
        );
        await bt.setMicrophone(false);
        voiceCollector.isRecording = false;
        break;
      case 23:
        // Subcmd 23 (0x17) = TouchPad pressed and held.
        // Left temple holds to dictate; right temple toggles a running capture.
        if (side == GlassSide.right) {
          if (_isCapturing) {
            await _finishDictation(side);
          } else {
            await _beginDictation(side);
          }
        } else {
          await _beginDictation(side);
        }
        break;

      case 24:
        // Subcmd 24 (0x18) = TouchPad pressed and released.
        // Only the left temple is hold-to-record; the right one toggles on
        // press, so its release carries no meaning.
        if (side != GlassSide.left) {
          debugPrint('[$side] Right touchpad released, toggle handled on press');
          break;
        }

        if (_isCapturing) {
          await _finishDictation(side);
        } else {
          // A release with no hold before it is a tap, a gesture nothing else
          // uses. It brings back what just went past.
          await _recallNotification();
        }
        break;

      default:
        debugPrint('[$side] Unknown Even AI subcommand: $subcmd');
    }
  }

  void handleMicResponse(GlassSide side, int status, int enable) {
    if (status == RESPONSE_SUCCESS) {
      debugPrint(
        '[$side] Mic ${enable == 1 ? "enabled" : "disabled"} successfully',
      );
    } else if (status == RESPONSE_FAILURE) {
      debugPrint('[$side] Failed to ${enable == 1 ? "enable" : "disable"} mic');
      final bt = BluetoothManager();
      bt.setMicrophone(enable == 1);
    }
  }

  // Make this function async
  Future<void> handleVoiceData(
    GlassSide side,
    int seq,
    List<int> voiceData,
  ) async {
    debugPrint(
      '[$side] Received voice data chunk: seq=$seq, length=${voiceData.length}',
    );

    final usingGlassesMic = await _useGlassesMicrophone();
    final isRecording = voiceCollector.isRecording;
    debugPrint(
        '[$side] Voice data: usingGlassesMic=$usingGlassesMic, isRecording=$isRecording');

    // Only buffer when the glasses microphone is the active source.
    if (usingGlassesMic && isRecording) {
      debugPrint('[$side] Adding voice chunk to collector');
      voiceCollector.addChunk(seq, voiceData);
    } else if (!usingGlassesMic) {
      // The phone microphone feeds the platform recogniser directly, so the
      // glasses stream is not buffered at all in that mode.
      debugPrint('[$side] Phone microphone in use, not buffering');
    } else {
      debugPrint('[$side] Not recording, discarding voice data');
    }

    // This check seems redundant now as stop command (24) handles mic disabling
    // final bt = BluetoothManager();
    // if (!voiceCollector.isRecording && ! _isListening) { // Check both states
    //   bt.setMicrophone(false);
    // }
  }

  void handleQuickNoteCommand(GlassSide side, List<int> data) {
    // Quick note events from the glasses firmware are ignored because
    // the right touchpad press is already handled by handleEvenAICommand
    // (0xF5 subcmd 23/24). Processing both would cause a double-toggle,
    // immediately starting and stopping the conversation recording.
    debugPrint('[$side] Quick note event received, ignoring (handled by EvenAI command)');
  }

  void handleQuickNoteAudioData(GlassSide side, List<int> data) async {
    // Quick note audio data is no longer fetched — the right-side touchpad
    // now triggers conversation recording instead. Discard any stale packets.
    debugPrint('[$side] Discarding quick note audio data (conversation mode active)');
  }

  /// Dispose of all resources to prevent memory leaks
  void dispose() {
    _stopListening();
    // Note: speech_to_text doesn't require explicit disposal
  }
}

// Voice data buffer to collect chunks
class VoiceDataCollector {
  final Map<int, List<int>> _chunks = {};
  int seqAdd = 0;
  final m = Mutex();

  bool isRecording = false;

  Future<void> addChunk(int seq, List<int> data) async {
    await m.acquire();
    if (seq == 255) {
      seqAdd += 255;
    }
    _chunks[seqAdd + seq] = data;
    m.release();
  }

  List<int> getAllData() {
    List<int> complete = [];
    final keys = _chunks.keys.toList()..sort();

    for (int key in keys) {
      complete.addAll(_chunks[key]!);
    }
    return complete;
  }

  Future<List<int>> getAllDataAndReset() async {
    await m.acquire();
    final data = getAllData();
    reset();
    m.release();

    return data;
  }

  /// Get a snapshot of all buffered data without clearing the buffer.
  /// Used for periodic live transcription during ongoing recording.
  Future<List<int>> getBufferedDataSnapshot() async {
    await m.acquire();
    final data = getAllData();
    m.release();
    return data;
  }

  void reset() {
    _chunks.clear();
    seqAdd = 0;
  }
}
