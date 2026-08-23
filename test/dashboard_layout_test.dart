import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';

/// The layout command, byte for byte.
///
/// It matters because the sync timer resends this every sixty seconds. It
/// used to resend a hardcoded dual layout, so any arrangement the wearer
/// chose was overwritten a minute later — the calendar pane appeared to
/// load and then vanish, which looked like the calendar failing rather
/// than the layout being reset on a timer.
void main() {
  group('The command matches the constants observed from the official app',
      () {
    test('dual', () {
      final built = DashboardLayoutCommand.build(
        mode: DashboardMode.dual,
        pane: DashboardPane.notes,
        sequence: 0x1E,
      );
      expect(built, [
        ...DashboardLayout.DASHBOARD_CHANGE_COMMAND,
        ...DashboardLayout.DASHBOARD_DUAL,
      ]);
    });

    test('full', () {
      final built = DashboardLayoutCommand.build(
        mode: DashboardMode.full,
        pane: DashboardPane.notes,
        sequence: 0x08,
      );
      expect(built, [
        ...DashboardLayout.DASHBOARD_CHANGE_COMMAND,
        ...DashboardLayout.DASHBOARD_FULL,
      ]);
    });

    test('minimal', () {
      final built = DashboardLayoutCommand.build(
        mode: DashboardMode.minimal,
        pane: DashboardPane.notes,
        sequence: 0x31,
      );
      expect(built, [
        ...DashboardLayout.DASHBOARD_CHANGE_COMMAND,
        ...DashboardLayout.DASHBOARD_MINIMAL,
      ]);
    });
  });

  group('The pane is a distinct byte from the mode', () {
    test('changing the pane changes only the last byte', () {
      final notes = DashboardLayoutCommand.build(
        mode: DashboardMode.dual,
        pane: DashboardPane.notes,
        sequence: 1,
      );
      final calendar = DashboardLayoutCommand.build(
        mode: DashboardMode.dual,
        pane: DashboardPane.calendar,
        sequence: 1,
      );

      expect(notes.length, calendar.length);
      expect(notes.sublist(0, notes.length - 1),
          calendar.sublist(0, calendar.length - 1));
      expect(notes.last, isNot(calendar.last));
    });
  });
}
