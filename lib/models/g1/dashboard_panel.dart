import 'dart:convert';
import 'dart:typed_data';

import 'package:g1_extended/models/g1/glasses_settings.dart';

/// Feeding the dashboard's secondary pane with our own content.
///
/// The pane the official app fills with news and a walking map is not a
/// closed surface: the same 0x06 command that sets the layout also carries
/// the pane's contents, under two sub-commands the layout code never used.
/// News takes a source and a body; the map pane takes a one-bit image the
/// size of the pane, with a small sprite that can be moved over it.
///
/// The shapes below were worked out by Egor Koleda (radioegor146) in
/// `even-utils`, and are reimplemented here from the protocol they describe
/// rather than copied: that repository carries no licence. What is verified
/// is the framing — the outer packet matches, byte for byte, the layout
/// command this app has always sent. What is not verified is anything on a
/// lens; none of this has been seen on real glasses yet.
abstract final class DashboardPanel {
  /// Same command as the layout: the sub-command tells the two apart.
  static const int command = 0x06;

  /// Sub-commands of 0x06.
  static const int layoutSubcommand = 0x06;
  static const int newsSubcommand = 0x05;
  static const int mapSubcommand = 0x07;

  /// The payload is split at 180 bytes, the same limit the notification and
  /// allow-list commands use.
  static const int chunkBytes = 180;

  /// Sync ids start high and count up, which is what the official app does
  /// and what the glasses echo back in their reply.
  static const int firstSyncId = 0x80;

  /// `06 <length u16le> <syncId> <data>`, the length counting the header.
  static List<int> frame(int syncId, List<int> data) {
    final length = 1 + 2 + 1 + data.length;
    return [
      command,
      length & 0xFF,
      (length >> 8) & 0xFF,
      syncId & 0xFF,
      ...data,
    ];
  }

  /// `<sub> <total u16le> <index u16le> <chunk>`, index counting from one.
  static List<int> transfer(
    int subcommand,
    int total,
    int index,
    List<int> chunk,
  ) {
    return [
      subcommand,
      total & 0xFF,
      (total >> 8) & 0xFF,
      index & 0xFF,
      (index >> 8) & 0xFF,
      ...chunk,
    ];
  }

  /// Splits a payload and wraps every piece, sync ids counting up.
  static List<List<int>> split(
    int subcommand,
    List<int> payload, {
    int syncId = firstSyncId,
  }) {
    final chunks = <List<int>>[];
    for (var i = 0; i < payload.length; i += chunkBytes) {
      final end = (i + chunkBytes < payload.length) ? i + chunkBytes : payload.length;
      chunks.add(payload.sublist(i, end));
    }
    if (chunks.isEmpty) chunks.add(const <int>[]);

    return [
      for (var i = 0; i < chunks.length; i++)
        frame(
          (syncId + i) & 0xFF,
          transfer(subcommand, chunks.length, i + 1, chunks[i]),
        ),
    ];
  }
}

/// What the news pane is doing while it has nothing to show.
enum NewsDisplayMode {
  loading(0x00),
  noDataSelected(0x01),
  showNews(0x02),
  unknown3(0x03),
  showMoreSources(0x04);

  const NewsDisplayMode(this.id);
  final int id;
}

/// Whether a slot is being written or emptied.
enum NewsOperation {
  unknown(0x00),
  update(0x01),
  delete(0x02);

  const NewsOperation(this.id);
  final int id;
}

/// What the map pane is doing.
enum MapDisplayMode {
  loading(0x00),
  reduceMovement(0x01),
  updatingMap(0x02),
  showMap(0x03);

  const MapDisplayMode(this.id);
  final int id;
}

/// One news entry: where it comes from, and what it says.
class NewsCard {
  NewsCard({required this.source, required this.text});

  /// At most 64 bytes once encoded.
  final String source;

  /// At most 280 bytes once encoded.
  final String text;

  static const int maxSourceBytes = 64;
  static const int maxTextBytes = 280;

  /// `01 <len u8> <source> 02 <len u16le> <text>`.
  ///
  /// Both fields are counted in bytes rather than characters, and both are
  /// truncated on a character boundary rather than refused: a headline one
  /// accent too long is still a headline worth showing.
  List<int> encode() {
    final rawSource = _clip(source, maxSourceBytes);
    final rawText = _clip(text, maxTextBytes);

    return [
      0x01,
      rawSource.length & 0xFF,
      ...rawSource,
      0x02,
      rawText.length & 0xFF,
      (rawText.length >> 8) & 0xFF,
      ...rawText,
    ];
  }

  static List<int> _clip(String value, int limit) {
    final encoded = utf8.encode(value);
    if (encoded.length <= limit) return encoded;

    // Cut on a character boundary. Truncating the bytes instead would split
    // an accent in half and leave the field unreadable at the far end.
    final out = <int>[];
    for (final rune in value.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (out.length + bytes.length > limit) break;
      out.addAll(bytes);
    }
    return out;
  }
}

/// The news pane, written slot by slot.
abstract final class DashboardNews {
  /// Slots run from one to four.
  static const int firstSlot = 1;
  static const int lastSlot = 4;

  /// `<mode> <pane> <newsMode> <slot> <operation> [card]`, chunked.
  static List<List<int>> write({
    required DashboardMode mode,
    required int slot,
    NewsDisplayMode displayMode = NewsDisplayMode.showNews,
    NewsOperation operation = NewsOperation.update,
    NewsCard? card,
    int syncId = DashboardPanel.firstSyncId,
  }) {
    if (slot < firstSlot || slot > lastSlot) {
      throw ArgumentError.value(slot, 'slot', 'must be $firstSlot to $lastSlot');
    }

    final payload = <int>[
      mode.id,
      DashboardPane.news.id,
      displayMode.id,
      slot,
      operation.id,
      ...?card?.encode(),
    ];
    return DashboardPanel.split(
      DashboardPanel.newsSubcommand,
      payload,
      syncId: syncId,
    );
  }

  /// Empties a slot.
  static List<List<int>> clear({
    required DashboardMode mode,
    required int slot,
    int syncId = DashboardPanel.firstSyncId,
  }) {
    return write(
      mode: mode,
      slot: slot,
      displayMode: NewsDisplayMode.noDataSelected,
      operation: NewsOperation.delete,
      syncId: syncId,
    );
  }
}

/// The map pane: an image the size of the pane, and a sprite on top of it.
abstract final class DashboardMap {
  /// The pane is wider when the dashboard is in dual mode than in full,
  /// because full mode keeps room for the agenda beside it.
  static const int dualWidth = 376;
  static const int fullWidth = 296;
  static const int height = 136;

  /// The sprite the official app uses for "you are here".
  static const int cursorWidth = 32;
  static const int cursorHeight = 32;

  static int widthFor(DashboardMode mode) =>
      mode == DashboardMode.dual ? dualWidth : fullWidth;

  /// How many bytes an image of that pane weighs, packed.
  static int imageBytesFor(DashboardMode mode) => widthFor(mode) * height ~/ 8;

  /// `<mode> <pane> <mapMode> 01 <image>`, chunked.
  static List<List<int>> image({
    required DashboardMode mode,
    required Uint8List packed,
    MapDisplayMode displayMode = MapDisplayMode.updatingMap,
    int syncId = DashboardPanel.firstSyncId,
  }) {
    final expected = imageBytesFor(mode);
    if (packed.length != expected) {
      throw ArgumentError(
        'a ${widthFor(mode)}x$height pane packs into $expected bytes, '
        'not ${packed.length}',
      );
    }

    final payload = <int>[
      mode.id,
      DashboardPane.navigation.id,
      displayMode.id,
      0x01,
      ...packed,
    ];
    return DashboardPanel.split(
      DashboardPanel.mapSubcommand,
      payload,
      syncId: syncId,
    );
  }

  /// `<mode> <pane> <mapMode> <x u16le> <y u16le> <sprite>`, one packet.
  static List<int> cursor({
    required DashboardMode mode,
    required int x,
    required int y,
    required Uint8List packed,
    MapDisplayMode displayMode = MapDisplayMode.showMap,
    int syncId = DashboardPanel.firstSyncId,
  }) {
    const expected = cursorWidth * cursorHeight ~/ 8;
    if (packed.length != expected) {
      throw ArgumentError(
        'a ${cursorWidth}x$cursorHeight sprite packs into $expected bytes, '
        'not ${packed.length}',
      );
    }

    final payload = <int>[
      mode.id,
      DashboardPane.navigation.id,
      displayMode.id,
      x & 0xFF,
      (x >> 8) & 0xFF,
      y & 0xFF,
      (y >> 8) & 0xFF,
      ...packed,
    ];
    return DashboardPanel.frame(
      syncId,
      DashboardPanel.transfer(DashboardPanel.mapSubcommand, 1, 1, payload),
    );
  }

  /// A "you are here" sprite: a ring with a dot in it.
  ///
  /// A ring rather than a disc on purpose. The lens is see-through, so every
  /// lit pixel is a piece of the world the wearer stops seeing; an outline
  /// says the same thing as a filled shape and costs a tenth of the view.
  static Uint8List cursorSprite() {
    final pixels = Uint8List(cursorWidth * cursorHeight);
    const centre = cursorWidth / 2 - 0.5;
    const outer = 12.0;
    const inner = 9.5;

    for (var y = 0; y < cursorHeight; y++) {
      for (var x = 0; x < cursorWidth; x++) {
        final dx = x - centre;
        final dy = y - centre;
        final distance = dx * dx + dy * dy;
        final onRing = distance <= outer * outer && distance >= inner * inner;
        final onDot = distance <= 3 * 3;
        if (onRing || onDot) pixels[y * cursorWidth + x] = 1;
      }
    }
    return pack(pixels, width: cursorWidth, height: cursorHeight);
  }

  /// A chart that makes a geometry or packing mistake obvious at a glance.
  ///
  /// A one-pixel border says whether the pane is the size we believe it is:
  /// a missing edge means the width is wrong. A diagonal from corner to
  /// corner says whether the rows are in the order we think. And the three
  /// pixels at the start of the fourth row say which end of a byte comes
  /// first — they sit at the left of the pane if the low bit leads, and
  /// jump to the right of an eight-pixel group if it does not.
  static Uint8List testPattern(DashboardMode mode) {
    final width = widthFor(mode);
    final pixels = Uint8List(width * height);

    void set(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return;
      pixels[y * width + x] = 1;
    }

    for (var x = 0; x < width; x++) {
      set(x, 0);
      set(x, height - 1);
    }
    for (var y = 0; y < height; y++) {
      set(0, y);
      set(width - 1, y);
    }
    for (var x = 0; x < width; x++) {
      set(x, x * (height - 1) ~/ (width - 1));
    }
    for (var x = 0; x < width; x += 8) {
      set(x, 2);
    }
    set(0, 3);
    set(1, 3);
    set(2, 3);

    return pack(pixels, width: width, height: height);
  }

  /// Packs one byte per pixel into one bit per pixel.
  ///
  /// Least significant bit first inside each byte, rows laid end to end with
  /// no padding — which is not how a BMP is stored, and is why a bitmap that
  /// displays perfectly well through the 0x15 command comes out as noise
  /// here. The width has to be a multiple of eight; 376 and 296 both are.
  static Uint8List pack(
    Uint8List pixels, {
    required int width,
    required int height,
  }) {
    if (width % 8 != 0) {
      throw ArgumentError.value(width, 'width', 'must be a multiple of 8');
    }
    if (pixels.length != width * height) {
      throw ArgumentError(
        'expected ${width * height} pixels, got ${pixels.length}',
      );
    }

    final packed = Uint8List(width * height ~/ 8);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (pixels[row + x] == 0) continue;
        packed[(row + x) ~/ 8] |= 1 << (x % 8);
      }
    }
    return packed;
  }
}
