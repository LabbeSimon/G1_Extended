import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/bluetooth_reciever.dart';

/// The glasses' microphone, wherever the audio actually lands.
///
/// Voice packets arrive at the isolate holding the Bluetooth link — the
/// background service — while the screens that want them run in the
/// interface. Each isolate has its own BluetoothReciever and therefore its
/// own buffer, so the captions screen was draining a collector nothing ever
/// filled: the microphone was on, the glasses were sending, and the screen
/// stayed empty with nothing to explain it.
///
/// This is the one place that knows where the audio is. When the link is in
/// this isolate the local buffer is drained directly; otherwise the owner is
/// asked to forward, and the packets come back over the service bus. Callers
/// see one stream either way.
class GlassesAudio {
  GlassesAudio._internal();
  static final GlassesAudio singleton = GlassesAudio._internal();
  factory GlassesAudio() => singleton;

  /// Bus event names, shared with the service.
  static const String startEvent = 'glassesAudioStart';
  static const String stopEvent = 'glassesAudioStop';
  static const String chunkEvent = 'glassesAudioChunk';

  /// How often the buffer is emptied. Fast enough that a recogniser hears
  /// speech as it happens, slow enough not to spend the whole event loop
  /// on empty drains.
  static const Duration drainInterval = Duration(milliseconds: 200);

  final StreamController<Uint8List> _chunks =
      StreamController<Uint8List>.broadcast();

  /// Encoded LC3 as it arrives. Decoding is the caller's business — the
  /// decoder is a native call and belongs where the result is used.
  Stream<Uint8List> get chunks => _chunks.stream;

  Timer? _localDrain;
  StreamSubscription<Map<String, dynamic>?>? _busChunks;
  bool _running = false;

  bool get isRunning => _running;

  /// True when this isolate can hear the glasses itself.
  bool get _hearsDirectly {
    final bluetooth = BluetoothManager.singleton;
    return bluetooth.leftGlass != null || bluetooth.rightGlass != null;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;

    // The microphone command relays on its own when this isolate has no
    // link, so it is correct from either side.
    await BluetoothManager.singleton.setMicrophone(true);

    if (_hearsDirectly) {
      debugPrint('GlassesAudio: draining the local buffer');
      _startLocalDrain();
      return;
    }

    debugPrint('GlassesAudio: asking the owner to forward');
    _busChunks = FlutterBackgroundService().on(chunkEvent).listen((event) {
      final raw = event?['bytes'];
      if (raw is! List) return;
      final bytes = Uint8List.fromList(
        [for (final b in raw) if (b is int) b & 0xFF],
      );
      if (bytes.isNotEmpty && !_chunks.isClosed) _chunks.add(bytes);
    });
    FlutterBackgroundService().invoke(startEvent);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _localDrain?.cancel();
    _localDrain = null;
    await _busChunks?.cancel();
    _busChunks = null;

    if (!_hearsDirectly) FlutterBackgroundService().invoke(stopEvent);

    final receiver = BluetoothReciever();
    receiver.voiceCollector.isRecording = false;
    receiver.voiceCollector.reset();

    await BluetoothManager.singleton.setMicrophone(false);
  }

  void _startLocalDrain() {
    final receiver = BluetoothReciever();
    receiver.voiceCollector.reset();
    receiver.voiceCollector.isRecording = true;

    _localDrain = Timer.periodic(drainInterval, (_) async {
      final encoded = await receiver.voiceCollector.getAllDataAndReset();
      if (encoded.isEmpty || _chunks.isClosed) return;
      _chunks.add(Uint8List.fromList(encoded));
    });
  }

  /// Runs in the owning isolate: forwards what it hears to whoever asked.
  ///
  /// Only while asked. Pushing audio across the bus unrequested would spend
  /// the radio, the bus and the battery on packets nobody is listening to.
  static void serveFrom(ServiceInstance service) {
    Timer? drain;
    final receiver = BluetoothReciever();

    service.on(startEvent).listen((_) {
      drain?.cancel();
      receiver.voiceCollector.reset();
      receiver.voiceCollector.isRecording = true;
      debugPrint('GlassesAudio: forwarding to the interface');

      drain = Timer.periodic(drainInterval, (_) async {
        final encoded = await receiver.voiceCollector.getAllDataAndReset();
        if (encoded.isEmpty) return;
        service.invoke(chunkEvent, {'bytes': encoded});
      });
    });

    service.on(stopEvent).listen((_) {
      drain?.cancel();
      drain = null;
      receiver.voiceCollector.isRecording = false;
      receiver.voiceCollector.reset();
      debugPrint('GlassesAudio: forwarding stopped');
    });
  }
}
