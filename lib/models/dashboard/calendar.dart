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
    final fpCals = calendarBox.values.toList();

    final items = <DashboardItem>[];

    for (var cal in fpCals) {
      if (!cal.enabled) {
        continue;
      }

      final events = await deviceCal.retrieveEvents(
          cal.id,
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
