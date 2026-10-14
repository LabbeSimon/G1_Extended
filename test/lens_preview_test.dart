import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/glasses_settings.dart';
import 'package:g1_extended/models/g1/note_slots.dart';
import 'package:g1_extended/widgets/lens_preview.dart';

/// The dashboard preview, laid out as the official app previews it: status
/// always, the calendar beside it in full, the chosen widget in full and
/// dual, nothing else in minimal.
void main() {
  Future<void> show(
    WidgetTester tester, {
    DashboardMode mode = DashboardMode.full,
    DashboardPane pane = DashboardPane.notes,
    List<SlotContent> slots = const [],
    String? event,
    int? battery = 80,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LensPreview(
            now: DateTime(2026, 10, 14, 9, 41),
            temperature: '13',
            isDay: true,
            batteryPercent: battery,
            mode: mode,
            pane: pane,
            slots: slots,
            nextEvent: event,
          ),
        ),
      ));

  const note = SlotContent(name: 'Courses', text: 'lait, pain');

  testWidgets('full: status, the calendar beside it, the notes widget',
      (tester) async {
    await show(tester, slots: const [note]);
    expect(find.text('09:41'), findsOneWidget);
    expect(find.text('13°C'), findsOneWidget);
    expect(find.text('No upcoming event'), findsOneWidget);
    expect(find.text('Courses · lait, pain'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
  });

  testWidgets('dual: the widget beside the status, no calendar column',
      (tester) async {
    await show(tester, mode: DashboardMode.dual, slots: const [note]);
    expect(find.text('Courses · lait, pain'), findsOneWidget);
    expect(find.text('No upcoming event'), findsNothing);
  });

  testWidgets('minimal: the status alone', (tester) async {
    await show(tester, mode: DashboardMode.minimal, slots: const [note]);
    expect(find.text('09:41'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('No upcoming event'), findsNothing);
  });

  testWidgets('empty notes say how to make one', (tester) async {
    await show(tester, mode: DashboardMode.dual);
    expect(find.text('Hold the right temple to record a quick note.'),
        findsOneWidget);
  });

  testWidgets('the battery warning only when it is low', (tester) async {
    await show(tester, battery: 12);
    expect(find.text('12%'), findsOneWidget);
    await show(tester, battery: 80);
    expect(find.text('80%'), findsNothing);
  });

  testWidgets('the calendar widget shows the next event', (tester) async {
    await show(tester,
        mode: DashboardMode.dual,
        pane: DashboardPane.calendar,
        event: '10:00 Dentiste');
    expect(find.text('10:00 Dentiste'), findsOneWidget);
  });
}
