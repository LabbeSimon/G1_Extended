import 'package:flutter/material.dart';

import 'package:g1_extended/theme/app_theme.dart';

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

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.4;
    final capWidth = size.width * 0.07;
    final bodyWidth = size.width - capWidth - 2;

    final body = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      bodyWidth,
      size.height - stroke,
    );
    final radius = Radius.circular(size.height * 0.18);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = hollow ? AppColors.inkMuted : AppColors.ink;

    canvas.drawRRect(RRect.fromRectAndRadius(body, radius), outline);

    // The terminal nub on the right.
    final cap = Rect.fromLTWH(
      body.right + 2,
      size.height * 0.3,
      capWidth,
      size.height * 0.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cap, Radius.circular(capWidth / 2)),
      Paint()..color = hollow ? AppColors.inkMuted : AppColors.ink,
    );

    if (fraction <= 0) return;

    // Fill inset far enough that it never touches the outline.
    final inset = body.deflate(stroke + 1.2);
    if (inset.width <= 0) return;

    final fill = Rect.fromLTWH(
      inset.left,
      inset.top,
      inset.width * fraction.clamp(0.0, 1.0),
      inset.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, Radius.circular(size.height * 0.1)),
      Paint()..color = hollow ? AppColors.inkMuted : AppColors.ink,
    );

    if (charging) _paintBolt(canvas, body);
  }

  /// A bolt punched out of the fill, so it reads at any level.
  void _paintBolt(Canvas canvas, Rect body) {
    final w = body.width;
    final h = body.height;
    final path = Path()
      ..moveTo(body.left + w * 0.52, body.top + h * 0.12)
      ..lineTo(body.left + w * 0.38, body.top + h * 0.54)
      ..lineTo(body.left + w * 0.50, body.top + h * 0.54)
      ..lineTo(body.left + w * 0.44, body.top + h * 0.90)
      ..lineTo(body.left + w * 0.62, body.top + h * 0.44)
      ..lineTo(body.left + w * 0.50, body.top + h * 0.44)
      ..close();

    canvas.drawPath(path, Paint()..blendMode = BlendMode.clear);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fraction != fraction ||
      old.charging != charging ||
      old.hollow != hollow;
}
