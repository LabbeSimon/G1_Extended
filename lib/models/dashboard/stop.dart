import 'package:g1_extended/models/dashboard/dashboard.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'stop.g.dart';

@HiveType(typeId: 1)
class StopItem {
  @HiveField(0)
  String title;
  @HiveField(1)
  DateTime time;
  @HiveField(2)
  late String uuid;

  StopItem({
    required this.title,
    required this.time,
    String? uuid,
  }) {
    this.uuid = uuid ?? Uuid().v4();
  }

  DashboardItem toDashboardItem() {
    return DashboardItem(
      title: title,
      hour: time.toLocal().hour,
      minute: time.toLocal().minute,
    );
  }
}
