import 'package:g1_extended/models/g1/note.dart';

abstract class DashboardWidget {
  int getPriority();
  Future<List<Note>> generateDashboardItems() {
    throw UnimplementedError();
  }
}
