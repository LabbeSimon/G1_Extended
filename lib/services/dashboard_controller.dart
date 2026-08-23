import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';

/// Keeps the glasses' dashboard arranged the way the wearer arranged it.
///
/// This used to hold a hardcoded DASHBOARD_DUAL that nothing ever changed,
/// and the sync timer resent it every sixty seconds. So the arrangement
/// could be set — from this app or the official one — and a minute later
/// it was silently forced back to dual. That is why the calendar pane would
/// appear to load and then vanish: it was not failing, it was being
/// overwritten on a timer.
///
/// The layout now comes from the stored preference, so resending it is what
/// it was meant to be — a way to restore the wearer's choice after the
/// glasses have been reset or reconnected — rather than an override.
class DashboardController {
  static final DashboardController _singleton = DashboardController._internal();

  factory DashboardController() => _singleton;

  DashboardController._internal();

  int _sequence = 0;

  /// The stored arrangement, or the sensible default when nothing is stored.
  Future<(DashboardMode, DashboardPane)> storedLayout() async {
    final prefs = await SharedPreferences.getInstance();

    final modeIndex = prefs.getInt('dashboard_mode') ?? DashboardMode.dual.index;
    final paneIndex =
        prefs.getInt('dashboard_pane') ?? DashboardPane.notes.index;

    return (
      DashboardMode
          .values[modeIndex.clamp(0, DashboardMode.values.length - 1)],
      DashboardPane
          .values[paneIndex.clamp(0, DashboardPane.values.length - 1)],
    );
  }

  Future<List<Uint8List>> updateDashboardCommand() async {
    final (mode, pane) = await storedLayout();

    // A fresh sequence byte each time: the firmware uses it to tell one
    // write from the next, and a repeat can read as no change at all.
    _sequence = (_sequence + 1) & 0xFF;

    return [
      DashboardLayoutCommand.build(
        mode: mode,
        pane: pane,
        sequence: _sequence,
      ),
    ];
  }

  /// The raw constants remain for the debug screen, which sends them
  /// deliberately to see what the firmware does with each.
  static const List<int> dual = DashboardLayout.DASHBOARD_DUAL;
}
