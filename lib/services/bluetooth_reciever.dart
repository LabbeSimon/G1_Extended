import 'dart:async';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/case_battery.dart';
import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/state_event.dart';
import 'package:g1_extended/services/glasses_event_log.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';
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
  final GlassSide? side;
  _PendingReply(this.completer, this.accept, this.side);
}

class BluetoothReciever {
  static final BluetoothReciever singleton = BluetoothReciever._internal();

  final voiceCollector = VoiceDataCollector();

  /// The voice note being fetched from the glasses' flash, if any.
  VoiceNoteDownload? _noteDownload;
  int? _noteDownloadCrc;
  DateTime? _noteDownloadStarted;

  /// How long a download may stay unfinished before a new list replaces it.
  /// The official app gives a transfer ten seconds.
  static const Duration _noteDownloadStall = Duration(seconds: 10);

  /// Recordings saved during this run, by the crc the glasses list them with.
  /// One still listed after its delete is not fetched a second time — the
  /// official app uses the crc as a recording's identity the same way.
  final Set<int> _savedNoteCrcs = {};

  bool get _noteDownloadInFlight {
    final started = _noteDownloadStarted;
    return _noteDownload != null &&
        started != null &&
        DateTime.now().difference(started) < _noteDownloadStall;
  }

  /// Asks the right temple which recordings its flash holds (0x1E sub 0x01).
  /// The answer carries the same list as a 0x21 announcement and goes through
  /// the same handler, so recordings made while disconnected are fetched too.
  Future<void> requestVoiceNoteList() async {
    if (_isCapturing || _noteDownloadInFlight) return;
    final right = BluetoothManager().rightGlass;
    if (right == null) return;
    await right.sendData(VoiceNote.buildListCommand(_noteSyncId++));
  }

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
  /// When [side] is given, the same command answered by the other temple is
  /// not taken for the reply.
  Future<List<int>?> awaitReply(
    int command, {
    Duration timeout = const Duration(seconds: 3),
    bool Function(List<int> data)? accept,
    GlassSide? side,
  }) async {
    // A second request for the same command supersedes the first.
    _pendingReplies.remove(command)?.completer.complete(const []);

    final completer = Completer<List<int>>();
    final pending = _PendingReply(completer, accept, side);
    _pendingReplies[command] = pending;

    try {
      final reply = await completer.future.timeout(timeout);
      return reply.isEmpty ? null : reply;
    } on TimeoutException {
      debugPrint('No reply to command 0x${command.toRadixString(16)}');
      return null;
    } finally {
      // Only this wait's own entry: a newer one for the same command may
      // already have taken the slot.
      if (identical(_pendingReplies[command], pending)) {
        _pendingReplies.remove(command);
      }
    }
  }

  /// Hands [data] to a waiting request, if one asked for this command and
  /// this packet is the sub-message it is waiting for.
  /// Returns true when the packet was consumed by a pending request.
  bool _deliverToPendingReply(GlassSide side, List<int> data) {
    final pending = _pendingReplies[data[0]];
    if (pending == null || pending.completer.isCompleted) return false;
    if (pending.side != null && pending.side != side) return false;
    if (pending.accept != null && !pending.accept!(data)) return false;
    pending.completer.complete(List<int>.unmodifiable(data));
    return true;
  }

  Future<void> receiveHandler(GlassSide side, List<int> data) async {
    if (data.isEmpty) return;

    // Settings replies are consumed by whoever asked for them.
    if (_deliverToPendingReply(side, data)) return;

    int command = data[0];

    switch (command) {
      case Commands.HEARTBEAT:
        break;
      case Commands.START_AI:
        // 0xF5 carries both the touchpad events and spontaneous state
        // changes. handleEvenAICommand only receives the subcommand, so
        // anything with a payload has to be read before dispatching or the
        // payload is simply dropped.
        // Recorded before anything is done with it, handled or not — and
        // before the case battery is peeled off below, which returns early
        // and would otherwise keep its own events out of the log.
        if (data.length >= 2) {
          GlassesEventLog.instance.record(side.name, data[1]);
        }

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
    // A running teleprompter takes the taps itself; switching the microphone
    // off here would also stop it following the reader's voice.
    if (GlassesTeleprompter.isActive && (subcmd == 0 || subcmd == 1)) return;

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
          debugPrint(
              '[$side] Right touchpad released, toggle handled on press');
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
        // Named where the community has a name for it, reported as unnamed
        // where nobody does — rather than "unknown" for both.
        debugPrint('[$side] ${StateEvent.describe(subcmd)}, not acted on');
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

    // Buffered for whoever opened the stream: glasses-microphone dictation,
    // the teleprompter's voice mode, live captions. Checking the dictation
    // microphone setting here as well used to starve the last two whenever
    // dictation was set to the phone — which never sets isRecording, so it
    // is unaffected either way.
    if (voiceCollector.isRecording) {
      voiceCollector.addChunk(seq, voiceData);
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

    // One transfer at a time: a list arriving mid-download would restart it
    // and throw away the chunks already in.
    if (_noteDownloadInFlight) {
      debugPrint('[$side] Voice note list during a download, deferred');
      return;
    }

    try {
      final notif = VoiceNoteNotification(Uint8List.fromList(data));
      debugPrint('[$side] Voice notes on glasses: ${notif.entries.length}');
      if (notif.entries.isEmpty) return;

      final right = BluetoothManager().rightGlass;
      if (right == null) {
        debugPrint('[$side] Right temple missing, cannot fetch voice notes');
        return;
      }

      VoiceNote? next;
      for (final entry in notif.entries) {
        if (entry.crc != null && _savedNoteCrcs.contains(entry.crc)) {
          // Already on the phone; its delete did not take. Ask again.
          right.sendData(entry.buildDeleteCommand(_noteSyncId++));
        } else {
          next ??= entry;
        }
      }
      if (next == null) return;

      _noteDownload = VoiceNoteDownload(next.index);
      _noteDownloadCrc = next.crc;
      _noteDownloadStarted = DateTime.now();
      debugPrint(
          '[$side] Fetching voice note #${next.index} from glasses flash');
      right.sendData(next.buildFetchCommand(_noteSyncId++));
    } catch (e) {
      debugPrint('[$side] Could not parse the voice note list: $e');
    }
  }

  /// One 0x1E audio chunk of the voice note being fetched.
  ///
  /// Layout read in the official Even app 1.6.5 (see docs/PROTOCOL_NOTES.md):
  /// `1E len len ? 02 total(LE16) index(LE16) id payload`. The transfer is
  /// done once as many packets as `total` have been counted, not when a
  /// particular index shows up — the firmware does not flag the last one.
  void handleQuickNoteAudioData(GlassSide side, List<int> data) async {
    if (data.length > 4 && data[4] == NoteSubCommands.REQUEST_AUDIO_INFO) {
      handleQuickNoteCommand(side, data); // The answer to a list request.
      return;
    }
    if (data.length > 4 && data[4] != NoteSubCommands.REQUEST_AUDIO_DATA) {
      debugPrint(
          '[$side] 0x1E subcmd 0x${data[4].toRadixString(16)}, not audio, ignored');
      return; // A text-note acknowledgement, not audio.
    }

    final download = _noteDownload;
    if (download == null) {
      debugPrint('[$side] Voice note audio with nothing being fetched');
      return;
    }
    if (!download.add(data)) {
      debugPrint('[$side] Voice note packet not for this download, ignored');
      return;
    }
    debugPrint(
        '[$side] Voice note chunk ${download.received}/${download.total}, '
        '${data.length - 10} audio bytes');

    if (!download.isComplete) return;

    debugPrint('[$side] Voice note complete: ${download.total} packets');
    final index = download.id;
    final crc = _noteDownloadCrc;
    final encoded = download.audio;
    _noteDownload = null;
    _noteDownloadCrc = null;
    _noteDownloadStarted = null;

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
      encoded: encoded,
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

    // Only now. The phone has it, so the slot can be freed. The id to delete
    // is the one the list gave, which is what the download echoed back.
    if (crc != null) _savedNoteCrcs.add(crc);
    await bt.rightGlass
        ?.sendData(VoiceNote(index: index).buildDeleteCommand(_noteSyncId++));

    await _transcribeKept(
      side: side,
      recording: kept.recording,
      pcm: kept.pcm,
      saveAsNote: true,
    );

    // Recordings are fetched one at a time; ask whether more are waiting.
    await requestVoiceNoteList();
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
