import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:g1_extended/models/g1/lens_framebuffer.dart';
import 'package:g1_extended/services/lens_emulator.dart';

/// Draws a decoded lens state as the pixels the wearer would see.
///
/// Kept out of the widget so the same rendering serves three callers that
/// have nothing else in common: the mirror on screen, the PNG handed to the
/// share sheet, and a test that wants to assert on pixels without a phone.
///
/// The glyphs are not the firmware's — Even Realities does not publish its
/// font. Flutter draws the text with real metrics and the result is
/// thresholded to one bit, which keeps accents and every script the phone
/// can draw honest; a hand-rolled 5x7 table would not.
abstract final class LensRenderer {
  /// Type size and leading that put five lines in 136 pixels, which is what
  /// the firmware fits, and about forty characters in the 488 pixel text
  /// column at font size 21.
  static const double fontSize = 21;

  /// 21 x 1.28 is 26.88, and five of those sit inside 136 pixels with a
  /// pixel to spare. 1.3 does not, by half a pixel — which is exactly the
  /// kind of half-pixel that clips the fifth line on the wearer's face.
  static const double lineHeight = 1.28;

  static TextStyle get style => const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: fontSize,
        height: lineHeight,
        fontFamily: 'monospace',
      );

  /// Draws the state, rasterises it, and thresholds it to one bit.
  ///
  /// Two passes rather than one: the first uses the real text engine, the
  /// second throws away everything the lens cannot show. Anti-aliasing that
  /// survives into the preview is a lie about a monochrome panel.
  static Future<LensFramebuffer> rasterise(LensState state) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = LensFramebuffer.width.toDouble();
    final height = LensFramebuffer.height.toDouble();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFF000000),
    );

    switch (state.surface) {
      case LensSurface.blank:
        break;
      case LensSurface.text:
        _paintText(canvas, state.text);
      case LensSurface.notification:
        _paintNotification(canvas, state);
      case LensSurface.image:
        await _paintImage(canvas, state);
    }

    final picture = recorder.endRecording();
    final raster = await picture.toImage(
      LensFramebuffer.width,
      LensFramebuffer.height,
    );
    picture.dispose();

    final rgba = await raster.toByteData(format: ui.ImageByteFormat.rawRgba);
    raster.dispose();
    if (rgba == null) return LensFramebuffer();

    return LensFramebuffer.fromRgba(rgba.buffer.asUint8List());
  }

  /// The framebuffer as an image, in the lens's green on black.
  static Future<ui.Image> toImage(LensFramebuffer frame) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.toRgba(),
      LensFramebuffer.width,
      LensFramebuffer.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// The framebuffer as a PNG, enlarged so its pixels survive a screen that
  /// is not a waveguide.
  ///
  /// Nearest-neighbour on purpose: a smoothed enlargement would invent grey
  /// where the lens only has on and off.
  static Future<Uint8List?> toPng(
    LensFramebuffer frame, {
    int scale = 2,
  }) async {
    final image = await toImage(frame);
    final width = LensFramebuffer.width * scale;
    final height = LensFramebuffer.height * scale;

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(
        0,
        0,
        LensFramebuffer.width.toDouble(),
        LensFramebuffer.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.none,
    );

    final scaled = await recorder.endRecording().toImage(width, height);
    image.dispose();
    final png = await scaled.toByteData(format: ui.ImageByteFormat.png);
    scaled.dispose();
    return png?.buffer.asUint8List();
  }

  static void _paintText(Canvas canvas, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: LensFramebuffer.textWidth.toDouble());
    painter.paint(canvas, Offset(LensFramebuffer.textLeft.toDouble(), 4));
  }

  static void _paintNotification(Canvas canvas, LensState state) {
    final body = state.notification?['ncs_notification'];
    final document = body is Map ? body : const <String, dynamic>{};
    final title =
        (document['title'] ?? document['display_name'] ?? '').toString();
    final message = (document['message'] ?? '').toString();

    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: [
          if (title.isNotEmpty)
            TextSpan(
              text: '$title\n',
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
          TextSpan(text: message),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 5,
      ellipsis: '…',
    )..layout(maxWidth: LensFramebuffer.textWidth.toDouble());
    painter.paint(canvas, Offset(LensFramebuffer.textLeft.toDouble(), 4));
  }

  static Future<void> _paintImage(Canvas canvas, LensState state) async {
    final bytes = state.image;
    if (bytes == null || bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      canvas.drawImageRect(
        frame.image,
        Rect.fromLTWH(
          0,
          0,
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        ),
        Rect.fromLTWH(
          0,
          0,
          LensFramebuffer.width.toDouble(),
          LensFramebuffer.height.toDouble(),
        ),
        Paint()..filterQuality = FilterQuality.none,
      );
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      // A transfer still in flight is not a decodable bitmap, and half a BMP
      // drawn as noise would read as a rendering bug rather than as what it
      // is. Leave the panel dark and let the chips say "image, incomplete".
    }
  }
}
