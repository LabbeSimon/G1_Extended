import 'package:flutter/material.dart';

import 'package:g1_extended/theme/app_theme.dart';

/// Artwork drawn on a grid, the way the glasses draw everything.
///
/// The G1 display is 640 by 200 monochrome pixels, and the official app's
/// iconography follows from that: shapes built out of squares rather than
/// curves. Material's icon font fights that — its glyphs are smooth vectors
/// that resample into mush at small sizes.
///
/// So the artwork here is literally a grid of characters. It scales by whole
/// pixels only, which is what keeps the edges hard at any size, and it is
/// legible in the source: the drawing and the code are the same thing.
class PixelArt extends StatelessWidget {
  const PixelArt({
    super.key,
    required this.rows,
    this.size = 24,
    this.color,
  });

  /// One string per row. `#` paints, anything else does not.
  final List<String> rows;

  /// Height in logical pixels. Width follows the grid's proportions.
  final double size;

  final Color? color;

  int get _gridHeight => rows.length;
  int get _gridWidth =>
      rows.fold(0, (widest, row) => row.length > widest ? row.length : widest);

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return SizedBox.square(dimension: size);

    // Whole-pixel scaling: a fractional scale is what turns crisp squares
    // into a blurred smear.
    final scale = (size / _gridHeight).floorToDouble().clamp(1.0, size);

    return CustomPaint(
      size: Size(_gridWidth * scale, _gridHeight * scale),
      painter: _PixelPainter(
        rows: rows,
        scale: scale,
        color: color ?? AppColors.ink,
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  const _PixelPainter({
    required this.rows,
    required this.scale,
    required this.color,
  });

  final List<String> rows;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      var x = 0;

      while (x < row.length) {
        if (row[x] != '#') {
          x++;
          continue;
        }

        // Runs of set pixels are drawn as one rectangle, which removes the
        // hairline seams that appear between adjacent rects at some scales.
        var run = 1;
        while (x + run < row.length && row[x + run] == '#') {
          run++;
        }

        canvas.drawRect(
          Rect.fromLTWH(x * scale, y * scale, run * scale, scale),
          paint,
        );
        x += run;
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.scale != scale || old.color != color || old.rows != rows;
}

/// The drawings themselves.
///
/// Proportions come from the manufacturer's own photographs: the case is a
/// rounded clamshell noticeably wider than it is tall, and the frames are
/// round lenses on a thin bridge.
abstract final class PixelArtwork {
  /// The glasses, seen from the front. The app's own motif.
  ///
  /// Two lenses of identical grids either side of a bridge, so the shape is
  /// symmetric by construction rather than by a steady hand.
  static const List<String> glasses = [
    '......................',
    '..####..........####..',
    '.#....#........#....#.',
    '#......########......#',
    '#......#......#......#',
    '#......#......#......#',
    '.#....#........#....#.',
    '..####..........####..',
    '......................',
  ];

  /// The charging case, closed. Wider than tall, with the clamshell seam
  /// across the middle, as in the manufacturer's photographs.
  static const List<String> caseClosed = [
    '....................',
    '...##############...',
    '..#..............#..',
    '.#................#.',
    '.#................#.',
    '.##################.',
    '.#................#.',
    '.#................#.',
    '..#..............#..',
    '...##############...',
    '....................',
  ];

  /// The case open: the lid lifted clear, the folded glasses in the
  /// tray below. Drawn as two rounded shapes rather than a faithful
  /// pair, because at twenty pixels across a faithful pair is a smudge.
  static const List<String> caseOpen = [
    '....................',
    '...##############...',
    '..#..............#..',
    '..#..............#..',
    '...##############...',
    '....................',
    '...##############...',
    '..#..............#..',
    '..#..####....####..#',
    '..#..#..#....#..#..#',
    '..#..####....####..#',
    '..#..............#..',
    '...##############...',
    '....................',
  ];

  /// A single lens, for places too small for the pair.
  static const List<String> lens = [
    '..####..',
    '.#....#.',
    '#......#',
    '#......#',
    '#......#',
    '.#....#.',
    '..####..',
  ];

  /// Brightness, set by hand.
  static const List<String> sun = [
    '............',
    '..#..#...#..',
    '...#.#..#...',
    '....####....',
    '...#....#...',
    '.#.#....#.#.',
    '...#....#...',
    '....####....',
    '...#.#..#...',
    '..#..#...#..',
    '............',
    '............',
  ];

  /// Brightness the glasses choose themselves.
  static const List<String> sunAuto = [
    '............',
    '...#.#..#...',
    '....####....',
    '...#....#...',
    '.#.#....#.#.',
    '...#....#...',
    '....####....',
    '...#.#..#...',
    '............',
    '....####....',
    '....#..#....',
    '....#..#....',
  ];

  /// Silent mode.
  /// The crescent that means silent, drawn solid.
  ///
  /// It was an outline before — a thin arc open to the right, which at
  /// button size read as the letter C and not as a moon at all. What makes
  /// a crescent legible is a solid body with the bite offset up and to the
  /// right, so the horns taper and the belly stays thick. Checked by
  /// rendering it, alongside a struck bell, a Zzz and the glasses struck
  /// through: all three of those were mush at twelve pixels.
  static const List<String> moon = [
    '............',
    '...####.....',
    '..######....',
    '.#######....',
    '.######.....',
    '.#####......',
    '.#####......',
    '.######.....',
    '.#######....',
    '..######....',
    '...####.....',
    '............',
  ];

  /// A quick note.
  static const List<String> note = [
    '............',
    '..########..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..#.##...#..',
    '..#......#..',
    '..########..',
    '............',
    '............',
  ];

  /// Dictation and the microphone settings.
  static const List<String> mic = [
    '............',
    '....####....',
    '....#..#....',
    '....#..#....',
    '....#..#....',
    '....#..#....',
    '...#....#...',
    '...#....#...',
    '....####....',
    '......##....',
    '....######..',
    '............',
  ];

  /// Live captions.
  static const List<String> captions = [
    '............',
    '..########..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..#.##.###..',
    '..#......#..',
    '..########..',
    '............',
    '............',
    '............',
    '............',
  ];

  /// The teleprompter, and ordered lists.
  static const List<String> list = [
    '............',
    '..#..#####..',
    '............',
    '..#..#####..',
    '............',
    '..#..#####..',
    '............',
    '..#..#####..',
    '............',
    '..#..#####..',
    '............',
    '............',
  ];

  /// The dashboard.
  static const List<String> grid = [
    '............',
    '..###..###..',
    '..#.#..#.#..',
    '..###..###..',
    '............',
    '..###..###..',
    '..#.#..#.#..',
    '..###..###..',
    '............',
    '............',
    '............',
    '............',
  ];

  /// Settings.
  /// Three mixer sliders. The knobs poke a pixel above and below their
  /// line, which is what keeps them knobs at small sizes — the previous
  /// drawing put single-pixel notches inside dense bars, and at button size
  /// it read as smeared text. Verified by rendering, like the rest.
  static const List<String> sliders = [
    '...##.......',
    '.##########.',
    '...##.......',
    '............',
    '.......##...',
    '.##########.',
    '.......##...',
    '............',
    '..##........',
    '.##########.',
    '..##........',
    '............',
  ];

  /// The speed readout.
  static const List<String> speed = [
    '............',
    '............',
    '...######...',
    '..#......#..',
    '.#....#...#.',
    '.#...#....#.',
    '.#..#.....#.',
    '#..........#',
    '#..........#',
    '#..#....#..#',
    '............',
    '............',
  ];

  /// Calendars and the agenda.
  static const List<String> calendar = [
    '............',
    '..#.....#...',
    '..########..',
    '..#......#..',
    '..########..',
    '..#.#.#..#..',
    '..#......#..',
    '..#.#.#..#..',
    '..#......#..',
    '..########..',
    '............',
    '............',
  ];

  /// Notifications.
  static const List<String> bell = [
    '............',
    '.....##.....',
    '....####....',
    '...#....#...',
    '..#......#..',
    '..#......#..',
    '.#........#.',
    '.##########.',
    '............',
    '.....##.....',
    '............',
    '............',
  ];

  /// Checklists, and anything confirmed.
  static const List<String> check = [
    '............',
    '..........#.',
    '.........#..',
    '#.......#...',
    '.#.....#....',
    '..#...#.....',
    '...#.#......',
    '....#.......',
    '............',
    '............',
    '............',
    '............',
  ];

  /// Time, and reminders.
  static const List<String> clock = [
    '............',
    '....####....',
    '..##....##..',
    '.#...#....#.',
    '.#...#....#.',
    '.#...####.#.',
    '.#........#.',
    '..##....##..',
    '....####....',
    '............',
    '............',
    '............',
  ];

  /// Fetching the offline speech model.
  static const List<String> download = [
    '............',
    '.....##.....',
    '.....##.....',
    '.....##.....',
    '..#..##..#..',
    '...#.##.#...',
    '....####....',
    '.....##.....',
    '............',
    '..########..',
    '............',
    '............',
  ];

  /// Checking again.
  static const List<String> refresh = [
    '............',
    '.....##.....',
    '...##..##...',
    '..#......#..',
    '.#........#.',
    '.#..........',
    '.#........#.',
    '..#......#..',
    '...##..##...',
    '.....##..#..',
    '..........##',
    '..........#.',
  ];

  /// Something needs attention.
  static const List<String> warning = [
    '.....##.....',
    '.....##.....',
    '....#..#....',
    '....#..#....',
    '...#....#...',
    '...#.##.#...',
    '..#..##..#..',
    '..#..##..#..',
    '.#........#.',
    '.#...##...#.',
    '.##########.',
    '............',
  ];

  /// Permissions.
  static const List<String> lock = [
    '............',
    '....####....',
    '...#....#...',
    '...#....#...',
    '..########..',
    '..#......#..',
    '..#..##..#..',
    '..#..##..#..',
    '..#......#..',
    '..########..',
    '............',
    '............',
  ];

  /// About.
  static const List<String> info = [
    '............',
    '....####....',
    '..##....##..',
    '.#...##...#.',
    '.#........#.',
    '.#...##...#.',
    '.#....#...#.',
    '.#...###..#.',
    '..##....##..',
    '....####....',
    '............',
    '............',
  ];

  /// The assistant.
  static const List<String> chat = [
    '............',
    '..########..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..#.###..#..',
    '..#......#..',
    '..#####..#..',
    '...#.....#..',
    '...##.####..',
    '............',
    '............',
  ];
}
