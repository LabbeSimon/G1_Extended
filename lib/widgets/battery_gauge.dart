import 'package:flutter/material.dart';

import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// A line-art battery gauge, drawn rather than picked from an icon font.
///
/// Material's battery icons come in fixed steps and read as filled glyphs.
/// This one is a thin outline that fills proportionally, which matches the
/// heads-up display look and shows the actual level rather than a bucket.
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.percentage,
    this.charging = false,
    this.width = 26,
    this.showLabel = true,
    this.label,
  });

  /// 0-100, or null when the level is unknown.
  final int? percentage;
  final bool charging;
  final double width;
  final bool showLabel;

  /// Optional prefix, such as "L" or "R".
  final String? label;

  /// Below this the gauge draws hollow, as a quiet warning.
  static const int lowThreshold = 15;

  @override
  Widget build(BuildContext context) {
    final known = percentage != null;
    final level = (percentage ?? 0).clamp(0, 100);
    final isLow = known && level <= lowThreshold;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontFamily: AppTheme.technicalFont,
              fontSize: 12,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(width: 6),
        ],
        CustomPaint(
          size: Size(width, width * 0.5),
          painter: _BatteryPainter(
            fraction: known ? level / 100 : 0,
            charging: charging,
            hollow: !known || isLow,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 7),
          Text(
            known ? '$level%' : '--%',
            style: TextStyle(
              fontFamily: AppTheme.technicalFont,
              fontSize: 13,
              color: known ? AppColors.ink : AppColors.inkFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.fraction,
    required this.charging,
    required this.hollow,
  });

  final double fraction;
  final bool charging;
  final bool hollow;

  /// The battery drawn on a fixed grid of whole pixels, like every other
  /// glyph in the app. It used to be rounded rectangles with an anti-aliased
  /// bolt — the one smooth object on an interface drawn entirely in squares,
  /// which is exactly the kind of thing that looks like it wandered in from
  /// another application.
  ///
  /// The grid is 20 by 9: a 17-wide body with notched corners, a gap, and a
  /// 2-wide terminal nub. The fill occupies the 13 by 5 interior.
  static const int _cols = 20;
  static const int _rows = 9;

  /// The bolt. While charging it replaces the fill entirely: at thirteen by
  /// five pixels a level and a bolt drawn together are mush, and the exact
  /// percentage is written in text right beside the gauge anyway.
  static const List<String> _bolt = [
    '......###....',
    '.....###.....',
    '...######....',
    '.....###.....',
    '....###......',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Whole pixels only. A fractional cell is what turns crisp squares into
    // a smear, so the scale is floored and the drawing centred in the rest.
    final cell = (size.height / _rows).floorToDouble().clamp(1.0, 1000.0);
    final left = ((size.width - cell * _cols) / 2).floorToDouble();
    final top = ((size.height - cell * _rows) / 2).floorToDouble();

    // No anti-aliasing: these are meant to be squares, and blending their
    // edges is what put hairline seams between adjacent cells.
    final ink = Paint()
      ..isAntiAlias = false
      ..color = hollow ? AppColors.inkMuted : AppColors.ink;

    final lit = fraction <= 0
        ? 0
        : (fraction.clamp(0.0, 1.0) * _fillCols).round().clamp(1, _fillCols);

    // Runs, not cells: one rectangle per horizontal stretch, the same trick
    // PixelArt uses, so neighbouring cells cannot seam.
    for (var r = 0; r < _rows; r++) {
      var c = 0;
      while (c < _cols) {
        if (!_cellOn(c, r, lit)) {
          c++;
          continue;
        }
        var end = c;
        while (end + 1 < _cols && _cellOn(end + 1, r, lit)) {
          end++;
        }
        canvas.drawRect(
          Rect.fromLTWH(
              left + c * cell, top + r * cell, (end - c + 1) * cell, cell),
          ink,
        );
        c = end + 1;
      }
    }
  }

  bool _cellOn(int c, int r, int lit) {
    // The terminal nub, floating one cell off the body.
    if (c >= 18) return r >= 3 && r <= 5;
    if (c == 17) return false;

    // The body outline, corners notched the pixel-art way.
    final corner = (c == 0 || c == 16) && (r == 0 || r == 8);
    if (corner) return false;
    if (r == 0 || r == 8 || c == 0 || c == 16) return true;

    final interior = c >= 2 && c <= 14 && r >= 2 && r <= 6;
    if (!interior) return false;

    if (charging) {
      final bc = c - 2, br = r - 2;
      return _bolt[br][bc] == '#';
    }
    return (c - 2) < lit;
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fraction != fraction ||
      old.charging != charging ||
      old.hollow != hollow;
}


/// The pair's battery, as one reading unless the two temples disagree.
///
/// Showing both sides all the time is noise: they discharge together, so two
/// gauges repeat the same number twice. What matters is how long you have
/// left, which is the emptier side. The pair only splits apart when they have
/// genuinely drifted — one temple left out of the case, say — because that is
/// the moment the difference is worth knowing about.
class GlassesBattery extends StatelessWidget {
  const GlassesBattery({
    super.key,
    required this.left,
    required this.right,
    this.charging = false,
    this.gaugeWidth = defaultGaugeWidth,
  });

  final int? left;
  final int? right;
  final bool charging;
  final double gaugeWidth;

  /// Shared with the case readout, so the two batteries in the tile are
  /// drawn at the same size by the same widget.
  static const double defaultGaugeWidth = 26;

  /// Below this the two sides are treated as one reading.
  static const int splitThreshold = 10;

  /// True when the two sides are far enough apart to be worth showing apart.
  static bool shouldSplit(int? left, int? right) {
    if (left == null || right == null) return false;
    return (left - right).abs() >= splitThreshold;
  }

  /// The side that runs out first, which is the one that matters.
  static int? lowest(int? left, int? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left < right ? left : right;
  }

  /// The glasses' own glyph, mirroring the case's.
  ///
  /// The case line carried a pictogram and this one did not, so the two
  /// readings in the same tile were not each other's equals — the case
  /// looked labelled and the glasses looked like the default. Same glyph
  /// size, same colour, same side.
  static Widget _glyph() => const Padding(
        padding: EdgeInsets.only(left: 8),
        child: PixelArt(
          rows: PixelArtwork.glasses,
          size: 14,
          color: AppColors.inkMuted,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!shouldSplit(left, right)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BatteryGauge(
            percentage: lowest(left, right),
            charging: charging,
            width: gaugeWidth,
          ),
          _glyph(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BatteryGauge(
              label: 'L',
              percentage: left,
              charging: charging,
              width: gaugeWidth,
            ),
            _glyph(),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BatteryGauge(
              label: 'R',
              percentage: right,
              charging: charging,
              width: gaugeWidth,
            ),
            _glyph(),
          ],
        ),
      ],
    );
  }
}


/// The charging case's level, shown only once something has reported one.
///
/// The glasses do not always know it: they learn it from the case, and only
/// while docked or shortly after. An empty space is more honest than a stale
/// number, so this renders nothing at all until there is something to say.
class CaseBatteryReadout extends StatelessWidget {
  const CaseBatteryReadout({
    super.key,
    required this.percentage,
    this.suspected = false,
  });

  final int? percentage;

  /// True when the value came from a byte believed to be the case level
  /// rather than the documented state change.
  final bool suspected;

  @override
  Widget build(BuildContext context) {
    final value = percentage;
    if (value == null) return const SizedBox.shrink();

    // A guess is not shown at all. It used to appear with a question mark,
    // on the reasoning that a marked guess beats no information — but a
    // number on a screen is read as a number, the mark is not, and being
    // told 40% when the case holds 90% is worse than being told nothing.
    // The byte it came from is consistent with the case level and equally
    // consistent with a duplicate of something else; until a capture
    // settles that, silence is the honest output.
    if (suspected) return const SizedBox.shrink();

    // The same gauge as the glasses' own line, at the same width, labelled
    // with the case glyph where the pair's line carries L and R. The case
    // used to get a tiny icon and a bare number beside the glasses' full
    // gauge — two batteries in the same tile drawn by two different
    // languages, which read as one of them mattering less.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BatteryGauge(
          percentage: value,
          width: GlassesBattery.defaultGaugeWidth,
        ),
        const SizedBox(width: 8),
        const PixelArt(
          rows: PixelArtwork.caseClosed,
          size: 14,
          color: AppColors.inkMuted,
        ),
      ],
    );
  }
}
