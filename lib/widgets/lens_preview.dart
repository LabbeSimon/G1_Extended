import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/models/g1/note_slots.dart';
import 'package:g1_extended/theme/app_theme.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// The glasses' dashboard, laid out the way the official app previews it.
///
/// A status block that is always there — the time large, the date, the
/// weather, a low-battery warning when there is one — then what the mode
/// adds: in full, the next calendar event under the status and the chosen
/// widget beside it; in dual, the widget beside the status alone; in
/// minimal, the status and nothing else. The arrangement follows the
/// official app's preview; the glyphs and icons are this app's own.
///
/// Drawn at the lens's own 640 by 200 and scaled to fit, so the proportions
/// cannot drift with the phone's width. The slot contents come from the same
/// plan that is written to the glasses.
class LensPreview extends StatelessWidget {
  const LensPreview({
    super.key,
    required this.now,
    required this.temperature,
    this.isDay,
    this.batteryPercent,
    required this.mode,
    required this.pane,
    required this.slots,
    required this.nextEvent,
  });

  final DateTime now;

  /// Already formatted, "18" or "--".
  final String temperature;

  /// Null when there is no weather yet.
  final bool? isDay;

  /// The lower of the two temples, null before the first reading.
  final int? batteryPercent;

  final DashboardMode mode;
  final DashboardPane pane;

  /// The slots as they stand, empty entries omitted — the same contents the
  /// glasses are written from.
  final List<SlotContent> slots;

  final String? nextEvent;

  /// The lens, in its own pixels.
  static const double width = 640;
  static const double height = 200;
  static const double aspect = width / height;

  /// Below this the status shows the warning the glasses show.
  static const int lowBattery = 20;

  /// How many note slots the glasses have.
  static const int noteSlots = 4;

  static const Color _ground = Color(0xFF050506);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          color: _ground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.tile, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
              child: _layout(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout() {
    switch (mode) {
      case DashboardMode.full:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _status(),
                  const Spacer(),
                  _calendarSide(),
                ],
              ),
            ),
            _divider(),
            Expanded(child: _widgetArea()),
          ],
        );
      case DashboardMode.dual:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 230, child: _status(dateFirst: true)),
            _divider(),
            Expanded(child: _widgetArea()),
          ],
        );
      case DashboardMode.minimal:
        return Align(
          alignment: Alignment.centerLeft,
          child: _status(dateFirst: true),
        );
    }
  }

  /// Time, date, weather, and the battery warning when it applies. Dual and
  /// minimal put the date above the time, full puts it under.
  Widget _status({bool dateFirst = false}) {
    final date = _text(DateFormat('EEE dd/MM').format(now), muted: true);
    final low = batteryPercent != null && batteryPercent! < lowBattery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dateFirst) date,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shrinks rather than overflows: the column is fixed, the
            // glyphs are whatever the phone's monospace face makes them.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _text(DateFormat('HH:mm').format(now), size: 48),
              ),
            ),
            if (low) ...[
              const SizedBox(width: 14),
              const PixelArt(
                rows: PixelArtwork.warning,
                size: 22,
                color: AppColors.ink,
              ),
              const SizedBox(width: 6),
              _text('$batteryPercent%', muted: true),
            ],
          ],
        ),
        if (!dateFirst) date,
        const SizedBox(height: 4),
        Row(
          children: [
            PixelArt(
              rows: isDay == false ? PixelArtwork.moon : PixelArtwork.sun,
              size: 22,
              color: AppColors.inkMuted,
            ),
            const SizedBox(width: 8),
            Flexible(child: _text('$temperature°C', muted: true)),
          ],
        ),
      ],
    );
  }

  /// The next event, under the status in full mode.
  Widget _calendarSide() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PixelArt(
            rows: PixelArtwork.calendar,
            size: 22,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _text(nextEvent ?? 'No upcoming event',
                muted: nextEvent == null, lines: 2),
          ),
        ],
      );

  /// The chosen widget, beside the status in full and dual.
  Widget _widgetArea() {
    switch (pane) {
      case DashboardPane.notes:
        return _panel(
          PixelArtwork.note,
          'Notes',
          trailing: slots.isEmpty ? null : '${slots.length}/$noteSlots',
          lines: slots.isEmpty
              ? const ['Hold the right temple to record a quick note.']
              : [for (final entry in slots.take(3)) _slotLine(entry)],
          muted: slots.isEmpty,
        );
      case DashboardPane.calendar:
        return _panel(
          PixelArtwork.calendar,
          'Calendar',
          lines: [nextEvent ?? 'No upcoming event'],
          muted: nextEvent == null,
        );
      case DashboardPane.stock:
        return _panel(PixelArtwork.list, 'Stocks',
            lines: const ['Your watch list, as the glasses chart it.'],
            muted: true);
      case DashboardPane.news:
        return _panel(PixelArtwork.list, 'News',
            lines: const ['Headlines from the sources you chose.'],
            muted: true);
      case DashboardPane.navigation:
        return _panel(PixelArtwork.lens, 'Map',
            lines: const ['Your route, while you navigate.'], muted: true);
      case DashboardPane.empty:
        return const SizedBox.shrink();
    }
  }

  Widget _panel(
    List<String> icon,
    String title, {
    String? trailing,
    required List<String> lines,
    bool muted = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PixelArt(rows: icon, size: 22, color: AppColors.ink),
            const SizedBox(width: 10),
            Expanded(child: _text(title)),
            if (trailing != null) _text(trailing, muted: true),
          ],
        ),
        const SizedBox(height: 10),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _text(line, muted: muted, lines: muted ? 2 : 1),
          ),
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 22),
        color: AppColors.tile,
      );

  /// "Courses · lait, pain" — the name, then the first line of the body,
  /// because a title alone shows the arrangement but not the content, and
  /// the lens shows both.
  static String _slotLine(SlotContent entry) {
    final firstLine = entry.text.split('\n').first.trim();
    if (firstLine.isEmpty || firstLine == entry.name) return entry.name;
    return '${entry.name} · $firstLine';
  }

  Widget _text(
    String value, {
    double size = 22,
    bool muted = false,
    int lines = 1,
  }) {
    return Text(
      value,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppTheme.technicalFont,
        fontSize: size,
        height: 1.15,
        color: muted ? AppColors.inkMuted : AppColors.ink,
      ),
    );
  }
}
