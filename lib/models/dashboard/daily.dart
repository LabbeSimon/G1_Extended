import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:hive/hive.dart';

part 'daily.g.dart';

@HiveType(typeId: 0)
class DailyItem {
  @HiveField(0)
  String title;
  @HiveField(1)
  int? hour;
  @HiveField(2)
  int? minute;

  DailyItem({
    required this.title,
    this.hour,
    this.minute,
  });

  DashboardItem toDashboardItem() {
    return DashboardItem(
      title: title,
      hour: hour,
      minute: minute,
    );
  }
}
