import 'dart:typed_data';

/// The lens as pixels, not as bytes.
///
/// Every other model here describes what the glasses are *told*. This one
/// describes what the wearer would *see*, which is a different thing and the
/// one that actually goes wrong: a line that runs off the panel, a page that
/// needed two screens and got one, a bitmap that dithered into a smear. None
/// of that shows up in a byte log, and none of it can be caught without the
/// glasses on your face — unless the app draws the panel itself.
///
/// One byte per pixel rather than one bit. 576 by 136 is 78 kB that way and
/// 10 kB packed, and at this size the packing costs more arithmetic than the
/// memory is worth: every drawing routine stays a single line.
class LensFramebuffer {
  /// The bitmap canvas the protocol actually drives, and the size every BMP
  /// sent to the glasses is expected to have (see `lib/utils/bitmap.dart`).
  ///
  /// Not to be confused with the panel's advertised 640x200: that is the
  /// optics' own resolution, and it is not what arrives over BLE.
  static const int width = 576;
  static const int height = 136;

  /// The usable text column, centred.
  ///
  /// The firmware keeps a margin on both sides and composes its text inside
  /// 488 pixels. Anything the app lays out against the full 576 will look
  /// right here and be clipped on the wearer's face.
  static const int textWidth = 488;
  static const int textLeft = (width - textWidth) ~/ 2;

  LensFramebuffer()
      : pixels = Uint8List(width * height);

  LensFramebuffer.fromPixels(this.pixels)
      : assert(pixels.length == width * height);

  /// 0 for a dark pixel, 1 for a lit one. Row-major, top row first.
  final Uint8List pixels;

  void clear() => pixels.fillRange(0, pixels.length, 0);

  void set(int x, int y, {bool on = true}) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    pixels[y * width + x] = on ? 1 : 0;
  }

  bool get(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    return pixels[y * width + x] == 1;
  }

  void fillRect(int x, int y, int w, int h, {bool on = true}) {
    final x0 = x < 0 ? 0 : x;
    final x1 = (x + w) > width ? width : (x + w);
    if (x0 >= x1) return;
    final value = on ? 1 : 0;
    final y0 = y < 0 ? 0 : y;
    final y1 = (y + h) > height ? height : (y + h);
    for (var row = y0; row < y1; row++) {
      pixels.fillRange(row * width + x0, row * width + x1, value);
    }
  }

  /// How many pixels are lit. The cheapest possible "something rendered".
  int get lit {
    var total = 0;
    for (final p in pixels) {
      total += p;
    }
    return total;
  }

  /// The share of the panel that is lit, from 0 to 1.
  ///
  /// On a see-through display this is not an aesthetic measure: every lit
  /// pixel is a piece of the world the wearer stops seeing. Designs built
  /// for the G2 by people who measure this land between three and four per
  /// cent per screen, and outline shapes rather than filled ones are how
  /// they get there. Worth watching whenever a banner or a bitmap looks
  /// heavy on the face without looking heavy in the preview.
  double get inkRatio => lit / (width * height);

  /// The last row holding anything, or -1 on an empty panel.
  ///
  /// A last lit row sitting on [height] minus one is the sign that content
  /// ran past the bottom of the lens instead of fitting on it.
  int get lastLitRow {
    for (var y = height - 1; y >= 0; y--) {
      final start = y * width;
      for (var x = 0; x < width; x++) {
        if (pixels[start + x] != 0) return y;
      }
    }
    return -1;
  }

  /// True when a column outside the text margin is lit.
  ///
  /// The panel does not stop at 488 pixels, the *readable* part does, so
  /// this is a warning and not an error — a full-width bitmap is legitimate.
  bool get spillsOutsideTextColumn {
    for (var y = 0; y < height; y++) {
      final start = y * width;
      for (var x = 0; x < textLeft; x++) {
        if (pixels[start + x] != 0) return true;
      }
      for (var x = textLeft + textWidth; x < width; x++) {
        if (pixels[start + x] != 0) return true;
      }
    }
    return false;
  }

  /// Reads a rasterised RGBA buffer back as one bit per pixel.
  ///
  /// This is how text gets into the framebuffer: Flutter draws it with real
  /// glyphs and real metrics into an offscreen canvas, and the result is
  /// thresholded here. Drawing our own 5x7 font would be less code and a
  /// worse answer — it would lie about accents, about every non-Latin
  /// script, and about where a line actually breaks.
  factory LensFramebuffer.fromRgba(Uint8List rgba, {int threshold = 128}) {
    final frame = LensFramebuffer();
    final count = width * height;
    if (rgba.length < count * 4) {
      throw ArgumentError('expected ${count * 4} RGBA bytes, got ${rgba.length}');
    }
    for (var i = 0; i < count; i++) {
      final o = i * 4;
      // Luminance is overkill for what is already black-on-white; the green
      // channel alone is what the lens shows anyway.
      final value = rgba[o + 1];
      frame.pixels[i] = value >= threshold ? 1 : 0;
    }
    return frame;
  }

  /// Unpacks the 1-bit rows of a BMP payload, top row first.
  ///
  /// The glasses are sent a 1-bit BMP whose rows are padded to four bytes and
  /// stored bottom-up; this reverses both so that what was sent can be shown
  /// as what would be displayed.
  void blitPackedRows(Uint8List rows, {bool bottomUp = true}) {
    final rowBytes = ((width + 31) ~/ 32) * 4;
    for (var y = 0; y < height; y++) {
      final sourceRow = bottomUp ? (height - 1 - y) : y;
      final offset = sourceRow * rowBytes;
      if (offset + rowBytes > rows.length) continue;
      for (var x = 0; x < width; x++) {
        final byte = rows[offset + (x >> 3)];
        final on = (byte & (0x80 >> (x & 7))) != 0;
        pixels[y * width + x] = on ? 1 : 0;
      }
    }
  }

  /// Paints the framebuffer as RGBA, ready for `decodeImageFromPixels`.
  ///
  /// Colours are passed in rather than hard-coded: the mirror wants the
  /// lens's green on black, a screenshot or a test wants black on white.
  Uint8List toRgba({int onArgb = 0xFF7CFFB2, int offArgb = 0xFF000000}) {
    final out = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i++) {
      final argb = pixels[i] == 1 ? onArgb : offArgb;
      final o = i * 4;
      out[o] = (argb >> 16) & 0xFF;
      out[o + 1] = (argb >> 8) & 0xFF;
      out[o + 2] = argb & 0xFF;
      out[o + 3] = (argb >> 24) & 0xFF;
    }
    return out;
  }
}
