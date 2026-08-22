import 'package:flutter/material.dart';

import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// One cell of the Bento grid.
///
/// Flat: colour separates it from the page, never a shadow or a border.
/// The icon sits top-left, the label bottom-left, and whatever the tile is
/// actually reporting goes in between.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    this.icon,
    this.pixels,
    this.label,
    this.child,
    this.onTap,
    this.active = false,
    this.padding = AppMetrics.tilePadding,
  });

  final IconData? icon;

  /// Pixel artwork, preferred over [icon] when both are given. The rest of
  /// the interface is drawn on a grid; a smooth Material glyph beside it
  /// looks like it wandered in from another application.
  final List<String>? pixels;

  final String? label;
  final Widget? child;
  final VoidCallback? onTap;

  /// Renders in the lighter "engaged" shade — used for toggles that are on.
  final bool active;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppMetrics.tileRadius);

    return Material(
      color: active ? AppColors.tileActive : AppColors.tile,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pixels != null)
                PixelArt(rows: pixels!, size: 24, color: AppColors.ink)
              else if (icon != null)
                Icon(icon, size: 26, color: AppColors.ink),
              if (child != null) ...[
                if (pixels != null || icon != null)
                  const SizedBox(height: 12),
                Expanded(child: child!),
              ] else
                const Spacer(),
              if (label != null)
                Text(label!, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The faint engineering-blueprint grid behind the hero tile.
///
/// Deliberately low contrast: it should register as texture, not as content.
class DotMatrix extends StatelessWidget {
  const DotMatrix({super.key, this.spacing = 6, this.child});

  final double spacing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotMatrixPainter(spacing: spacing),
      child: child,
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter({required this.spacing});

  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.matrix;
    const radius = 0.6;

    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter oldDelegate) =>
      oldDelegate.spacing != spacing;
}

/// A labelled readout in the technical font, as seen on the glasses.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.value,
    this.unit,
    this.icon,
    this.muted = false,
  });

  final String value;
  final String? unit;
  final IconData? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.inkMuted : AppColors.ink;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.technicalFont,
            fontSize: 15,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        if (unit != null)
          Text(
            unit!,
            style: const TextStyle(
              fontFamily: AppTheme.technicalFont,
              fontSize: 12,
              color: AppColors.inkMuted,
            ),
          ),
      ],
    );
  }
}
