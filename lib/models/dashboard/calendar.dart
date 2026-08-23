import 'package:device_calendar/device_calendar.dart';
import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:hive/hive.dart';

part 'calendar.g.dart';

@HiveType(typeId: 2)
class DashboardCalendar {
  @HiveField(0)
  String id;
  @HiveField(1)
  bool enabled;

  DashboardCalendar({
    required this.id,
    required this.enabled,
  });
}

class DashboardCalendarComposer {
  final calendarBox = Hive.box<DashboardCalendar>('calendarBox');

  Future<List<DashboardItem>> toDashboardItems() async {
    final deviceCal = DeviceCalendarPlugin();

    // Asked about, never requested: this runs from the sync timer, and a
    // permission dialog popping out of a background refresh is how apps
    // train people to tap "deny". The permissions screen owns asking.
    final access = await deviceCal.hasPermissions();
    if (access.data != true) return const [];

    // Every calendar on the device, with the box holding only exclusions.
    //
    // It used to iterate the box itself — the list of calendars the user had
    // explicitly enabled. That list was seeded by opening the Calendars
    // screen, and by nothing else. So on a fresh install the agenda was
    // empty forever, permission granted or not, until a visit to a screen
    // nothing pointed at; "the calendar does not work even with access" was
    // this, both times it was reported. Same decision as notifications:
    // everything flows by default, the user excludes.
    final calendars = (await deviceCal.retrieveCalendars()).data ??
        const <Calendar>[];
    final excluded = {
      for (final stored in calendarBox.values)
        if (!stored.enabled) stored.id,
    };

    final items = <DashboardItem>[];

    for (final cal in calendars) {
      final id = cal.id;
      if (id == null || excluded.contains(id)) {
        continue;
      }

      final events = await deviceCal.retrieveEvents(
          id,
          RetrieveEventsParams(
            startDate: DateTime.now(),
            endDate: DateTime.now().add(const Duration(days: 1)),
          ));

      for (var event in events.data ?? []) {
        if (event.start == null) {
          continue;
        }
        if (!_isToday(event.start!)) {
          continue;
        }

        final start = event.start!;
        items.add(DashboardItem(
          title: event.title,
          hour: start.toLocal().hour,
          minute: start.toLocal().minute,
        ));
      }
    }

    return items;
  }

  bool _isToday(DateTime time) {
    time = time.toLocal();
    final now = DateTime.now().toLocal();
    return time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
  }
}
