import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:g1_extended/models/g1/lens_framebuffer.dart';
import 'package:g1_extended/services/lens_emulator.dart';

/// The lens drawn as pixels, from the packets the app actually sent.
///
/// [LensPreview] composes a plausible dashboard out of Flutter text at the
/// optics' 640x200 proportions. This is the other thing: 576x136, one bit per
/// pixel, fed by [LensEmulator] rather than by a parallel guess at what was
/// sent. It can therefore be wrong in the ways the glasses are wrong — a line
/// that runs past the text column, a page that needed two screens — which is
/// the entire point of looking at it.
///
/// The glyphs are not the firmware's: Even Realities does not publish its
/// font. Rendering with Flutter's own engine and thresholding the result to
/// one bit keeps accents, and every script the phone can draw, honest —
/// which hand-drawing a 5x7 table would not.
class LensPanel extends StatefulWidget {
  const LensPanel({
    super.key,
    required this.state,
    this.showReport = true,
  });

  final LensState state;

  /// The line of chips underneath: page, status byte, what overflowed.
  final bool showReport;

  /// Type size and leading that put five lines in 136 pixels, which is what
  /// the firmware fits, and about forty characters in the 488 pixel text
  /// column, which is what the community spec measures at 21 px.
  /// Above this, the lens is more screen than window.
  ///
  /// Not a hard rule: a photograph legitimately fills the panel. It is a
  /// number to notice, the way a designer notices a wall of text.
  static const double inkWarningPercent = 20;

  static const double fontSize = 21;

  /// 21 x 1.28 is 26.88, and five of those sit inside 136 pixels with a
  /// pixel to spare. 1.3 does not, by half a pixel — which is exactly the
  /// kind of half-pixel that clips the fifth line on the wearer's face.
  static const double lineHeight = 1.28;

  @override
  State<LensPanel> createState() => _LensPanelState();
}

class _LensPanelState extends State<LensPanel> {
  ui.Image? _image;
  LensFramebuffer? _frame;
  int _renderToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void didUpdateWidget(covariant LensPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) unawaited(_render());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Draws the state, rasterises it, and thresholds it to one bit.
  ///
  /// Two passes rather than one: the first uses the real text engine, the
  /// second throws away everything the lens cannot show. Anti-aliasing that
  /// survives into the preview is a lie about a monochrome panel.
  Future<void> _render() async {
    final token = ++_renderToken;
    final state = widget.state;

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
    if (rgba == null || token != _renderToken || !mounted) return;

    final frame = LensFramebuffer.fromRgba(rgba.buffer.asUint8List());
    final image = await _toImage(frame);
    if (token != _renderToken || !mounted) {
      image.dispose();
      return;
    }

    setState(() {
      _image?.dispose();
      _image = image;
      _frame = frame;
    });
  }

  Future<ui.Image> _toImage(LensFramebuffer frame) {
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

  void _paintText(Canvas canvas, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style()),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    )..layout(maxWidth: LensFramebuffer.textWidth.toDouble());
    painter.paint(canvas, Offset(LensFramebuffer.textLeft.toDouble(), 4));
  }

  void _paintNotification(Canvas canvas, LensState state) {
    final body = state.notification?['ncs_notification'];
    final document = body is Map ? body : const <String, dynamic>{};
    final title = (document['title'] ?? document['display_name'] ?? '')
        .toString();
    final message = (document['message'] ?? '').toString();

    final painter = TextPainter(
      text: TextSpan(
        style: _style(),
        children: [
          if (title.isNotEmpty)
            TextSpan(
              text: '$title\n',
              style: _style().copyWith(fontWeight: FontWeight.bold),
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

  Future<void> _paintImage(Canvas canvas, LensState state) async {
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

  TextStyle _style() => const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: LensPanel.fontSize,
        height: LensPanel.lineHeight,
        fontFamily: 'monospace',
      );

  @override
  Widget build(BuildContext context) {
    final image = _image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: LensFramebuffer.width / LensFramebuffer.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF05070A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF1E2A24)),
            ),
            child: image == null
                ? const SizedBox.expand()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: RawImage(
                      image: image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      isAntiAlias: false,
                    ),
                  ),
          ),
        ),
        if (widget.showReport) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _chips()),
        ],
      ],
    );
  }

  List<Widget> _chips() {
    final state = widget.state;
    final frame = _frame;
    final chips = <Widget>[_chip(state.surface.name)];

    if (state.surface == LensSurface.text) {
      chips.add(_chip('page ${state.page}/${state.maxPages}'));
      chips.add(_chip(
        'status 0x${state.screenStatus.toRadixString(16).padLeft(2, '0')}',
      ));
    }
    if (state.surface == LensSurface.image && !state.imageComplete) {
      chips.add(_chip('incomplete'));
    }
    if (state.brightness != null) chips.add(_chip('lum ${state.brightness}'));
    if (state.silent) chips.add(_chip('silent'));

    if (frame != null) {
      // A blank lens after a clear is not a fault; a screen that was asked
      // to show something and lit nothing is.
      if (frame.lit == 0 && state.surface != LensSurface.blank) {
        chips.add(_chip('rien d\'allumé', warn: true));
      }
      // The bottom row lit means the content had nowhere left to go: what
      // sits below it was cut, and the wearer never sees it.
      final ink = frame.inkRatio * 100;
      if (frame.lit > 0) {
        chips.add(_chip(
          'encre ${ink.toStringAsFixed(1)} %',
          warn: ink > LensPanel.inkWarningPercent,
        ));
      }
      if (frame.lastLitRow >= LensFramebuffer.height - 1) {
        chips.add(_chip('déborde en bas', warn: true));
      }
      if (state.surface != LensSurface.image &&
          frame.spillsOutsideTextColumn) {
        chips.add(_chip('hors colonne 488', warn: true));
      }
    }
    final pane = state.paneTransfer;
    if (pane != null) {
      if (pane.kind == 'news') {
        final label = pane.source == null
            ? 'news ${pane.slot ?? '?'}'
            : 'news ${pane.slot ?? '?'} · ${pane.source}';
        chips.add(_chip(label));
      } else {
        chips.add(_chip('carte ${pane.index}/${pane.total}'));
      }
      if (!pane.complete) chips.add(_chip('transfert en cours', warn: true));
    }
    if (state.unhandled.isNotEmpty) {
      final last = state.unhandled.last.toRadixString(16).padLeft(2, '0');
      chips.add(_chip('${state.unhandled.length} inconnus, dern. 0x$last'));
    }
    return chips;
  }

  Widget _chip(String label, {bool warn = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? const Color(0x33FF6B4A) : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: warn ? const Color(0xFFFFB4A0) : const Color(0xFFBFC8C4),
        ),
      ),
    );
  }
}
