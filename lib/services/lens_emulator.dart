import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What the lens is currently showing, in the firmware's terms.
enum LensSurface {
  /// Nothing was ever sent, or the screen was cleared.
  blank,

  /// A text screen, possibly one page of several.
  text,

  /// A bitmap, whole or still arriving.
  image,

  /// A notification banner.
  notification,
}

/// What was last written to the dashboard's secondary pane.
@immutable
class PaneTransfer {
  const PaneTransfer({
    required this.kind,
    required this.index,
    required this.total,
    this.slot,
    this.source,
    this.text,
  });

  /// 'news' or 'map'.
  final String kind;

  /// Which packet of how many. A transfer stuck below [total] is a transfer
  /// the glasses never finished receiving.
  final int index;
  final int total;

  /// News only.
  final int? slot;
  final String? source;
  final String? text;

  bool get complete => index >= total;
}

/// A snapshot of the lens, rebuilt from the bytes the app actually wrote.
@immutable
class LensState {
  const LensState({
    this.surface = LensSurface.blank,
    this.text = '',
    this.page = 1,
    this.maxPages = 1,
    this.screenStatus = 0,
    this.image,
    this.imageComplete = false,
    this.notification,
    this.brightness,
    this.autoBrightness = false,
    this.silent = false,
    this.dashboardMode,
    this.dashboardPanel,
    this.paneTransfer,
    this.unhandled = const <int>[],
  });

  final LensSurface surface;

  final String text;
  final int page;
  final int maxPages;

  /// Kept raw, deliberately.
  ///
  /// The community spec reads the high nibble as the mode (0x30 Even AI,
  /// 0x70 plain text) and the low one as the action (0x01 new content);
  /// this app composes 0x20 | 0x10. A mirror that quietly normalised the
  /// byte would hide the one difference worth looking at on real glasses.
  final int screenStatus;

  /// The BMP payload as it was sent, address bytes stripped.
  final Uint8List? image;

  /// True once the end-of-transfer and CRC packets have both arrived.
  final bool imageComplete;

  /// The decoded notification document, or null if the chunks did not parse.
  final Map<String, dynamic>? notification;

  final int? brightness;
  final bool autoBrightness;
  final bool silent;

  /// 0 full, 1 dual, 2 minimal — the values the layout command carries.
  final int? dashboardMode;
  final int? dashboardPanel;

  /// The last thing written to the dashboard's secondary pane.
  ///
  /// Not drawn: the pane lives beside the lens surface this panel renders,
  /// and painting it here would be an invention. Reported instead, because
  /// a transfer that stalls at packet 12 of 36 is worth seeing.

  final PaneTransfer? paneTransfer;

  /// Opcodes seen and not understood, most recent last.
  ///
  /// Kept rather than dropped, for the same reason the SDK's monitor prints
  /// unknown sub-codes: the protocol is reverse-engineered, and the packets
  /// nobody decodes yet are the ones worth noticing.
  final List<int> unhandled;

  LensState copyWith({
    LensSurface? surface,
    String? text,
    int? page,
    int? maxPages,
    int? screenStatus,
    Uint8List? image,
    bool? imageComplete,
    Map<String, dynamic>? notification,
    int? brightness,
    bool? autoBrightness,
    bool? silent,
    int? dashboardMode,
    int? dashboardPanel,
    PaneTransfer? paneTransfer,
    List<int>? unhandled,
  }) {
    return LensState(
      surface: surface ?? this.surface,
      text: text ?? this.text,
      page: page ?? this.page,
      maxPages: maxPages ?? this.maxPages,
      screenStatus: screenStatus ?? this.screenStatus,
      image: image ?? this.image,
      imageComplete: imageComplete ?? this.imageComplete,
      notification: notification ?? this.notification,
      brightness: brightness ?? this.brightness,
      autoBrightness: autoBrightness ?? this.autoBrightness,
      silent: silent ?? this.silent,
      dashboardMode: dashboardMode ?? this.dashboardMode,
      dashboardPanel: dashboardPanel ?? this.dashboardPanel,
      paneTransfer: paneTransfer ?? this.paneTransfer,
      unhandled: unhandled ?? this.unhandled,
    );
  }
}

/// Rebuilds the lens's state from the packets the app sends it.
///
/// This is the half of a simulator that does not need a screen: give it the
/// same bytes [BluetoothManager] hands to the temples and it says what those
/// bytes amount to. It is deliberately a decoder and nothing else — the
/// drawing lives in the widget, and the tests can assert on the state
/// without a render at all.
///
/// It decodes what this app is known to send. Anything else is counted, not
/// guessed at: a mirror that invents a screen is worse than one that admits
/// it did not understand a packet.
class LensEmulator {
  /// The app's own mirror, fed by every write [BluetoothManager] makes.
  ///
  /// One instance rather than one per screen: what the lens shows is a
  /// property of the glasses, not of whoever happens to be looking at it,
  /// and a second emulator started halfway through a bitmap transfer would
  /// show half a bitmap for ever.
  static final LensEmulator mirror = LensEmulator();

  static const int _opText = 0x4E;
  static const int _opNotification = 0x4B;
  static const int _opBmpData = 0x15;
  static const int _opBmpEnd = 0x20;
  static const int _opBmpCrc = 0x16;
  static const int _opClear = 0x18;
  static const int _opBrightness = 0x01;
  static const int _opSilent = 0x03;
  static const int _opDashboard = 0x06;

  /// The four bytes every first bitmap packet carries before its data.
  static const List<int> _bmpAddress = [0x00, 0x1C, 0x00, 0x00];

  static const int _silentOn = 0x0C;

  /// How many unknown opcodes to remember. Enough to spot a pattern, few
  /// enough that a chatty firmware cannot grow the list without bound.
  static const int _unhandledDepth = 16;

  LensState _state = const LensState();
  LensState get state => _state;

  final _changes = StreamController<LensState>.broadcast();
  Stream<LensState> get changes => _changes.stream;

  final List<int> _textChunks = <int>[];
  final Map<int, List<int>> _notificationChunks = <int, List<int>>{};
  int _notificationTotal = 0;
  final List<int> _imageBytes = <int>[];
  bool _imageEnded = false;

  /// Feeds one outgoing write.
  void consume(List<int> packet) {
    if (packet.isEmpty) return;

    switch (packet[0]) {
      case _opText:
        _consumeText(packet);
      case _opNotification:
        _consumeNotification(packet);
      case _opBmpData:
        _consumeBmpData(packet);
      case _opBmpEnd:
        _imageEnded = true;
      case _opBmpCrc:
        _emit(_state.copyWith(
          surface: LensSurface.image,
          image: Uint8List.fromList(_imageBytes),
          imageComplete: _imageEnded,
        ));
      case _opClear:
        _reset();
        _emit(const LensState().copyWith(
          brightness: _state.brightness,
          autoBrightness: _state.autoBrightness,
          silent: _state.silent,
          dashboardMode: _state.dashboardMode,
          dashboardPanel: _state.dashboardPanel,
          unhandled: _state.unhandled,
        ));
      case _opBrightness:
        if (packet.length >= 3) {
          _emit(_state.copyWith(
            brightness: packet[1],
            autoBrightness: packet[2] == 0x01,
          ));
        }
      case _opSilent:
        if (packet.length >= 2) {
          _emit(_state.copyWith(silent: packet[1] == _silentOn));
        }
      case _opDashboard:
        _consumeDashboard(packet);
      default:
        _emit(_state.copyWith(unhandled: _remember(packet[0])));
    }
  }

  /// `4E seq total current status pos0 pos1 page maxPage <utf8>`
  void _consumeText(List<int> packet) {
    if (packet.length < 9) return;

    final total = packet[2];
    final current = packet[3];
    if (current == 0) _textChunks.clear();
    _textChunks.addAll(packet.sublist(9));
    if (current < total - 1) return;

    // A chunk boundary can fall inside a character, so the text is only
    // decoded once every piece has arrived.
    final text = utf8.decode(_textChunks, allowMalformed: true);
    _textChunks.clear();
    _emit(_state.copyWith(
      surface: LensSurface.text,
      text: text,
      screenStatus: packet[4],
      page: packet[7],
      maxPages: packet[8],
    ));
  }

  /// `4B notifyId total index <json chunk>`
  ///
  /// Four header bytes, notifyId included — the shape this app settled on
  /// after the three-byte one silently displayed nothing.
  void _consumeNotification(List<int> packet) {
    if (packet.length < 4) return;

    final total = packet[2];
    final index = packet[3];
    if (index == 0) _notificationChunks.clear();
    _notificationTotal = total;
    _notificationChunks[index] = packet.sublist(4);
    if (_notificationChunks.length < _notificationTotal) return;

    final assembled = <int>[];
    for (var i = 0; i < _notificationTotal; i++) {
      assembled.addAll(_notificationChunks[i] ?? const <int>[]);
    }
    _notificationChunks.clear();

    Map<String, dynamic>? document;
    try {
      final decoded = json.decode(utf8.decode(assembled, allowMalformed: true));
      if (decoded is Map<String, dynamic>) document = decoded;
    } on FormatException {
      document = null;
    }

    _emit(_state.copyWith(
      surface: LensSurface.notification,
      notification: document,
    ));
  }

  /// `15 seq [00 1C 00 00 when seq is 0] <chunk>`
  void _consumeBmpData(List<int> packet) {
    if (packet.length < 2) return;

    var start = 2;
    if (packet[1] == 0) {
      _imageBytes.clear();
      _imageEnded = false;
      final carriesAddress = packet.length >= 6 &&
          packet[2] == _bmpAddress[0] &&
          packet[3] == _bmpAddress[1] &&
          packet[4] == _bmpAddress[2] &&
          packet[5] == _bmpAddress[3];
      if (carriesAddress) start = 6;
    }
    _imageBytes.addAll(packet.sublist(start));
    _emit(_state.copyWith(
      surface: LensSurface.image,
      image: Uint8List.fromList(_imageBytes),
      imageComplete: false,
    ));
  }

  /// `06 len_lo len_hi syncId sub ...` — the framed shape, four header bytes.
  void _consumeDashboard(List<int> packet) {
    const int layoutSub = 0x06;
    const int newsSub = 0x05;
    const int mapSub = 0x07;
    if (packet.length < 5) {
      _emit(_state.copyWith(unhandled: _remember(packet[0])));
      return;
    }

    switch (packet[4]) {
      case layoutSub when packet.length >= 7:
        _emit(_state.copyWith(
          dashboardMode: packet[5],
          dashboardPanel: packet[6],
        ));
      case newsSub:
        _consumePane(packet, 'news');
      case mapSub:
        _consumePane(packet, 'map');
      default:
        _emit(_state.copyWith(unhandled: _remember(packet[0])));
    }
  }

  /// `<sub> <total u16le> <index u16le> <chunk>` inside the 0x06 frame.
  ///
  /// Only the first chunk carries the pane's own header, so only the first
  /// chunk can say what the transfer is about; the rest are counted.
  void _consumePane(List<int> packet, String kind) {
    if (packet.length < 9) {
      _emit(_state.copyWith(unhandled: _remember(packet[0])));
      return;
    }

    final total = packet[5] | (packet[6] << 8);
    final index = packet[7] | (packet[8] << 8);
    final body = packet.sublist(9);

    int? slot;
    String? source;
    String? text;
    if (kind == 'news' && index == 1 && body.length >= 5) {
      slot = body[3];
      final card = body.sublist(5);
      final fields = _readNewsFields(card);
      source = fields.$1;
      text = fields.$2;
    }

    _emit(_state.copyWith(
      paneTransfer: PaneTransfer(
        kind: kind,
        index: index,
        total: total,
        slot: slot ?? _state.paneTransfer?.slot,
        source: source ?? (index == 1 ? null : _state.paneTransfer?.source),
        text: text ?? (index == 1 ? null : _state.paneTransfer?.text),
      ),
    ));
  }

  /// `01 <len u8> <source> 02 <len u16le> <text>`.
  (String?, String?) _readNewsFields(List<int> card) {
    String? source;
    String? text;
    var at = 0;
    while (at < card.length) {
      final tag = card[at];
      if (tag == 0x01 && at + 1 < card.length) {
        final length = card[at + 1];
        final end = at + 2 + length;
        if (end > card.length) break;
        source = utf8.decode(card.sublist(at + 2, end), allowMalformed: true);
        at = end;
      } else if (tag == 0x02 && at + 2 < card.length) {
        final length = card[at + 1] | (card[at + 2] << 8);
        final end = at + 3 + length;
        if (end > card.length) break;
        text = utf8.decode(card.sublist(at + 3, end), allowMalformed: true);
        at = end;
      } else {
        break;
      }
    }
    return (source, text);
  }

  List<int> _remember(int opcode) {
    final seen = List<int>.from(_state.unhandled)..add(opcode);
    if (seen.length > _unhandledDepth) {
      seen.removeRange(0, seen.length - _unhandledDepth);
    }
    return List<int>.unmodifiable(seen);
  }

  void _reset() {
    _textChunks.clear();
    _notificationChunks.clear();
    _notificationTotal = 0;
    _imageBytes.clear();
    _imageEnded = false;
  }

  void _emit(LensState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  void dispose() {
    _changes.close();
  }
}
