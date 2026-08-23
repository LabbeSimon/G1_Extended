import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// The glasses' display, reproduced at its own proportions.
///
/// The lens is 640 by 200, and this draws the same layout the firmware
/// composes for the dashboard: the header line of time, date and battery,
/// then the body the configured mode dictates — everything in full, two
/// panes side by side, or the header alone in minimal. The slot titles come
/// from the same plan that is actually written to the glasses, not from a
/// separate guess, so the mirror cannot drift from the real thing.
///
/// It is an approximation of typography, not of truth: the firmware's exact
/// glyphs are its own, but what is shown, and where, is what the wearer
/// sees.
class LensPreview extends StatelessWidget {
  const LensPreview({
    super.key,
    required this.now,
    required this.temperature,
    required this.batteryLabel,
    required this.mode,
    required this.pane,
    required this.slots,
    required this.nextEvent,
  });

  final DateTime now;

  /// Already formatted, "18" or "--".
  final String temperature;

  /// Already formatted, "84%" or "--".
  final String batteryLabel;

  final DashboardMode mode;
  final DashboardPane pane;

  /// The four slot titles as they stand, empty entries omitted.
  final List<String> slots;

  final String? nextEvent;

  /// The lens's own proportions, 640 over 200.
  static const double aspect = 3.2;

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            if (mode != DashboardMode.minimal) ...[
              const SizedBox(height: 6),
              Expanded(child: _body()),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        _text(DateFormat('HH:mm').format(now), size: 14),
        const SizedBox(width: 10),
        _text(DateFormat('EEE dd/MM').format(now), muted: true),
        const Spacer(),
        _text('$temperature°', muted: true),
        const SizedBox(width: 10),
        _text(batteryLabel, muted: true),
      ],
    );
  }

  Widget _body() {
    switch (mode) {
      case DashboardMode.minimal:
        return const SizedBox.shrink();
      case DashboardMode.full:
        return _notes(slots);
      case DashboardMode.dual:
        final split = (slots.length / 2).ceil();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _notes(slots.take(split).toList())),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: AppColors.tile,
            ),
            Expanded(child: _paneBody(slots.skip(split).toList())),
          ],
        );
    }
  }

  Widget _paneBody(List<String> remainingSlots) {
    switch (pane) {
      case DashboardPane.notes:
        return _notes(remainingSlots);
      case DashboardPane.calendar:
        return _lines([nextEvent ?? 'No upcoming event']);
      case DashboardPane.navigation:
        return _lines(const ['Navigation']);
      case DashboardPane.stock:
        return _lines(const ['Stock graph']);
      case DashboardPane.news:
        return _lines(const ['News']);
      case DashboardPane.empty:
        return const SizedBox.shrink();
    }
  }

  Widget _notes(List<String> titles) => titles.isEmpty
      ? _lines(const ['No notes'])
      : _lines(titles.take(4).toList());

  Widget _lines(List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _text(line, muted: true, ellipsis: true),
          ),
      ],
    );
  }

  Widget _text(String value,
      {double size = 11, bool muted = false, bool ellipsis = false}) {
    return Text(
      value,
      maxLines: 1,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
      style: TextStyle(
        fontFamily: AppTheme.technicalFont,
        fontSize: size,
        height: 1.2,
        color: muted ? AppColors.inkMuted : AppColors.ink,
      ),
    );
  }
}
