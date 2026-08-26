import 'dart:async';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/case_battery.dart';
import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/dictation_service.dart';
import 'package:g1_extended/services/notification_history.dart';
import 'package:g1_extended/models/g1/voice_note.dart';
import 'package:g1_extended/services/speech_recognition_service.dart';
import 'package:g1_extended/services/voice_recordings.dart';
import 'package:g1_extended/utils/lc3.dart';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added import
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Command response status codes
const int RESPONSE_SUCCESS = 0xC9;
const int RESPONSE_FAILURE = 0xCA;

/// A completer waiting on a command byte, and optionally on which
/// sub-message of it — see [BluetoothReciever.awaitReply].
class _PendingReply {
  final Completer<List<int>> completer;
  final bool Function(List<int> data)? accept;
  _PendingReply(this.completer, this.accept);
}

class BluetoothReciever {
  static final BluetoothReciever singleton = BluetoothReciever._internal();

  final voiceCollector = VoiceDataCollector();

  /// Chunks of a voice note being fetched from the glasses' flash.
  final voiceCollectorNote = VoiceDataCollector();

  /// Rolls with each 0x1E exchange, echoed back by the firmware.
  int _noteSyncId = 0;

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
          saveAsNote: _captureSide == GlassSide.right,
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
  /// that byte is usually enough to match a reply to the request that asked
  /// for it. A few commands carry several distinct sub-messages under the
  /// same first byte — the calibration flow's 0x10 announces both "the
  /// begin step was accepted" and, separately, "the wearer confirmed" — and
  /// for those [_PendingReply.accept] tells the two apart.
  final Map<int, _PendingReply> _pendingReplies = {};

  /// Registers interest in the next response carrying [command].
  ///
  /// When [accept] is given, a reply that does not satisfy it is left for
  /// ordinary dispatch and waiting continues — otherwise the first packet
  /// with a matching command byte would end the wait, sub-message or not.
  ///
  /// Returns null if nothing arrives within [timeout], rather than hanging:
  /// the glasses silently ignore commands they do not understand.
  Future<List<int>?> awaitReply(
    int command, {
    Duration timeout = const Duration(seconds: 3),
    bool Function(List<int> data)? accept,
  }) async {
    // A second request for the same command supersedes the first.
    _pendingReplies.remove(command)?.completer.complete(const []);

    final completer = Completer<List<int>>();
    _pendingReplies[command] = _PendingReply(completer, accept);

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

  /// Hands [data] to a waiting request, if one asked for this command and
  /// this packet is the sub-message it is waiting for.
  /// Returns true when the packet was consumed by a pending request.
  bool _deliverToPendingReply(List<int> data) {
    final pending = _pendingReplies[data[0]];
    if (pending == null || pending.completer.isCompleted) return false;
    if (pending.accept != null && !pending.accept!(data)) return false;
    pending.completer.complete(List<int>.unmodifiable(data));
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
        debugPrint('[$side] 0x21 QUICK_NOTE, ${data.length} bytes');
        handleQuickNoteCommand(side, data);
        break;
      case Commands.QUICK_NOTE_ADD:
        debugPrint('[$side] 0x1E QUICK_NOTE_ADD, ${data.length} bytes');
        handleQuickNoteAudioData(side, data);
        break;

      default:
        debugPrint('[$side] Unknown command: 0x${command.toRadixString(16)}');
    }
  }

  /// True while a touchpad-initiated capture is running.
  bool _isCapturing = false;

  /// Which temple started the running capture.
  ///
  /// The two mean different things: the left talks to the glasses —
  /// commands, the assistant, plain display — while the right dictates a
  /// note. The phone-microphone path reports its result through a callback
  /// that has no idea which temple asked, so the side is kept here from
  /// begin to finish.
  GlassSide? _captureSide;

  /// Puts a recent notification back on the lens.
  ///
  /// Repeated taps walk further back, which is why the history keeps a
  /// cursor rather than only the newest.
  /// Whether we answer the left tap ourselves. Off by default: the glasses
  /// already do something with it.
  Future<bool> _recallOnLeftTap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('recall_on_left_tap') ?? false;
  }

  Future<void> _recallNotification() async {
    // The tap is handled in whichever isolate holds the glasses; the
    // notifications were recorded in whichever isolate the stream reached.
    // The file bridges the two — without this line, "Nothing recent" on a
    // phone that buzzed all morning.
    await NotificationHistory.singleton.ensureLoaded();
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
    _captureSide = side;

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

    // Saved before it is recognised, for the same reason as a fetched note:
    // the recogniser is the part that fails, and what someone said should
    // not depend on whether a model happened to be installed.
    final kept = await _keepAudio(
      side: side,
      encoded: Uint8List.fromList(encoded),
      source: RecordingSource.glassesLive,
    );

    if (kept == null) {
      debugPrint('[$side] Live capture could not be saved');
      try {
        await bt.sendPriorityText('Could not save that recording.');
      } catch (_) {}
      return;
    }

    await _transcribeKept(
      side: side,
      recording: kept.recording,
      pcm: kept.pcm,
      saveAsNote: side == GlassSide.right,
    );
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
          break;
        }

        // A tap on the left temple is the firmware's own gesture, and it
        // already means something there: on the dashboard it opens the
        // notification list, inside it it moves to the next one. Answering
        // it ourselves put two handlers on one gesture and the firmware won
        // — what the wearer saw was Even AI opening instead of a recall.
        //
        // So we stand aside by default. The recall still exists and is
        // still useful when the firmware's own list is not what you want;
        // it is behind a setting rather than fighting for the gesture.
        if (await _recallOnLeftTap()) {
          await _recallNotification();
        } else {
          debugPrint('[$side] Left tap left to the firmware');
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

  /// A 0x21 from the firmware: its flash holds recorded voice notes.
  ///
  /// The firmware records a quicknote on its own when the right touchbar is
  /// held; this used to be discarded entirely, so those recordings piled up
  /// in the glasses unheard. Now the newest is fetched, as Fahrplan does —
  /// the announcement is a list, not a touchpad event, so acting on it
  /// cannot double-toggle the dictation flow.
  void handleQuickNoteCommand(GlassSide side, List<int> data) {
    // Mid-capture the firmware is announcing the very speech the running
    // dictation is already streaming; fetching it too would save it twice.
    if (_isCapturing) {
      debugPrint('[$side] Voice note announced during capture, deferred');
      return;
    }

    try {
      final notif = VoiceNoteNotification(Uint8List.fromList(data));
      debugPrint('[$side] Voice notes on glasses: ${notif.entries.length}');
      if (notif.entries.isEmpty) return;

      voiceCollectorNote.reset();
      final entry = notif.entries.first;
      final right = BluetoothManager().rightGlass;
      if (right == null) {
        debugPrint(
            '[$side] Right temple missing, cannot fetch voice note #${entry.index}');
        return;
      }
      debugPrint(
          '[$side] Fetching voice note #${entry.index} from glasses flash');
      right.sendData(entry.buildFetchCommand(_noteSyncId++));
    } catch (e) {
      debugPrint('[$side] Could not parse the voice note list: $e');
    }
  }

  /// One 0x1E audio chunk of the voice note being fetched.
  ///
  /// Byte layout pinned by Fahrplan against real firmware: length, sync id,
  /// a constant 0x02, packet counts as uint16 pairs, the note's flash index
  /// plus one, then the LC3 audio itself.
  void handleQuickNoteAudioData(GlassSide side, List<int> data) async {
    if (data.length > 4 && data[4] != NoteSubCommands.REQUEST_AUDIO_DATA) {
      debugPrint(
          '[$side] 0x1E subcmd 0x${data[4].toRadixString(16)}, not audio, ignored');
      return; // A text-note acknowledgement, not audio.
    }
    if (data.length < 11) {
      debugPrint('[$side] Voice note packet too short: ${data.length} bytes');
      return;
    }

    int seq = data[3];
    int totalPackets = (data[5] << 8) | data[4];
    int currentPacket = (data[7] << 8) | data[6];
    int index = data[9] - 1;
    voiceCollectorNote.addChunk(seq, data.sublist(10));
    debugPrint(
        '[$side] Voice note chunk $currentPacket/$totalPackets, seq=$seq, ${data.length - 10} audio bytes');

    if (currentPacket + 2 != totalPackets) return;

    debugPrint('[$side] Voice note complete: $totalPackets packets');
    final encoded = voiceCollectorNote.getAllData();
    voiceCollectorNote.reset();

    if (encoded.isEmpty) {
      debugPrint('[$side] Voice note carried no audio; glasses copy kept');
      return;
    }

    // The audio goes to disk before anything else happens to it. What
    // follows — freeing the flash slot, transcribing — are both things
    // that used to be able to destroy a recording, and neither runs until
    // the phone holds its own copy.
    final kept = await _keepAudio(
      side: side,
      encoded: Uint8List.fromList(encoded),
      source: RecordingSource.glassesNote,
    );

    final bt = BluetoothManager();

    if (kept == null) {
      // Nothing reached disk, so the glasses hold the only copy and it
      // stays there. Deleting it now is precisely how a recording is lost
      // for good; a full flash is the lesser problem and it is recoverable.
      debugPrint(
          '[$side] Voice note could not be saved; leaving it on the glasses');
      try {
        await bt.sendPriorityText(
          'Could not save that recording.\nIt is still on the glasses.',
        );
      } catch (_) {}
      return;
    }

    // Only now. The phone has it, so the slot can be freed.
    await bt.rightGlass
        ?.sendData(VoiceNote(index: index + 1).buildDeleteCommand(_noteSyncId++));

    await _transcribeKept(
      side: side,
      recording: kept.recording,
      pcm: kept.pcm,
      saveAsNote: true,
    );
  }

  /// Decodes and stores captured audio, returning null only if nothing at
  /// all could be written.
  ///
  /// A failed LC3 decode is not a reason to lose the recording: the codec
  /// bytes are stored as they arrived so a working decoder can be pointed
  /// at them later. The one unrecoverable case — the write itself failing —
  /// is reported honestly to the caller, because the caller is about to
  /// decide whether to delete the other copy.
  Future<({Recording recording, Uint8List pcm})?> _keepAudio({
    required GlassSide side,
    required Uint8List encoded,
    required RecordingSource source,
  }) async {
    Uint8List pcm = Uint8List(0);
    try {
      pcm = await LC3.decodeLC3(encoded);
    } catch (e) {
      debugPrint('[$side] LC3 decoding failed: $e');
    }

    try {
      if (pcm.isNotEmpty) {
        final recording =
            await VoiceRecordings.singleton.savePcm(pcm, source: source);
        return (recording: recording, pcm: pcm);
      }

      debugPrint('[$side] LC3 gave no samples; keeping the raw codec bytes');
      final recording = await VoiceRecordings.singleton
          .saveUndecodedLc3(encoded, source: source);
      return (recording: recording, pcm: Uint8List(0));
    } catch (e) {
      debugPrint('[$side] Could not write the recording to disk: $e');
      return null;
    }
  }

  /// Runs speech recognition over audio that is already saved.
  ///
  /// Every failure here is annotated onto the stored recording rather than
  /// thrown away, because by this point the recording exists and none of
  /// these outcomes are a reason to pretend it does not.
  Future<void> _transcribeKept({
    required GlassSide side,
    required Recording recording,
    required Uint8List pcm,
    required bool saveAsNote,
  }) async {
    final store = VoiceRecordings.singleton;

    if (pcm.isEmpty) {
      // Raw LC3 was kept; there is nothing a recogniser could read.
      return;
    }

    try {
      final transcript =
          await SpeechRecognitionService.singleton.transcribeBytes(pcm);
      debugPrint('[$side] Transcribed: "$transcript"');

      if (transcript.trim().isEmpty) {
        await store.attachTranscriptError(
          recording.id,
          'Nothing intelligible was recognised. The audio is kept.',
        );
        return;
      }

      await store.attachTranscript(recording.id, transcript);
      await DictationService.singleton.record(
        transcript,
        saveAsNote: saveAsNote,
        recordingId: recording.id,
      );
    } on SpeechModelMissingException {
      await store.attachTranscriptError(
        recording.id,
        'No speech model installed. The audio is kept; install a model in '
        'Settings > Voice and it can be transcribed later.',
      );
      try {
        await BluetoothManager().sendPriorityText(
          'Recording saved.\nNo speech model — Settings > Voice.',
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[$side] Transcription failed: $e');
      await store.attachTranscriptError(
        recording.id,
        'Transcription failed. The audio is kept.',
      );
    }
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
