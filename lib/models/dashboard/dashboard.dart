import 'package:g1_extended/models/dashboard/calendar.dart';
import 'package:g1_extended/models/dashboard/checklist.dart';
import 'package:g1_extended/models/dashboard/daily.dart';
import 'package:g1_extended/models/dashboard/stop.dart';
import 'package:g1_extended/models/dashboard/dashboard_widget.dart';
import 'package:g1_extended/models/g1/note.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DashboardItem {
  final String title;
  final int? hour;
  final int? minute;

  DashboardItem({
    required this.title,
    this.hour,
    this.minute,
  });

  @override
  String toString() {
    return '${NoteSupportedIcons.CHECKBOX}${hour?.toString().padLeft(2, '0') ?? ''}:${minute?.toString().padLeft(2, '0') ?? ''} $title';
  }
}

class GlassesDashboard {
  static final GlassesDashboard _singleton = GlassesDashboard._internal();
  factory GlassesDashboard() {
    return _singleton;
  }
  GlassesDashboard._internal();

  List<DashboardItem> items = [];

  List<DashboardWidget> installedWidgets = [
  ];

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await Hive.openBox<DailyItem>('dailyBox');
    await Hive.openBox<DashboardCalendar>('calendarBox');
    await Hive.openBox<Checklist>('checklistBox');
    await Hive.openBox('notificationApps');
    try {
      await Hive.openLazyBox<StopItem>('stopBox');
    } catch (e) {
      debugPrint('Error while registering adapter: $e');
    }

    _initialized = true;
  }

  bool _isToday(DateTime time) {
    final now = DateTime.now();
    return time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
  }

  Future<void> _loadItems() async {
    await initialize();
    items.clear();

    final dailyBox = Hive.box<DailyItem>('dailyBox');
    items.addAll(dailyBox.values.map((e) => e.toDashboardItem()));

    final stopBox = Hive.lazyBox<StopItem>('stopBox');
    final List<StopItem> stops = [];
    for (var i = 0; i < stopBox.length; i++) {
      final item = await stopBox.getAt(i);
      if (item != null) {
        stops.add(item);
      }
    }

    final calComposer = DashboardCalendarComposer();
    final calendarItems = await calComposer.toDashboardItems();
    items.addAll(calendarItems);

    final todayStops = stops
        .where((element) =>
            _isToday(element.time) && element.time.isAfter(DateTime.now()))
        .toList();
    items.addAll(todayStops.map((e) => e.toDashboardItem()));
  }

  List<DashboardWidget> _getChecklists() {
    final List<DashboardWidget> widgets = [];
    final checklistBox =
        Hive.box<Checklist>('checklistBox');
    final allChecklists = checklistBox.values.toList();
    for (var list in allChecklists) {
      if (list.isShown) {
        widgets.add(list);
      }
    }

    return widgets;
  }

  Future<List<Note>> generateDashboardItems() async {
    await _loadItems();
    _sortItemsByTime();

    var widgets = installedWidgets.toList();
    widgets.sort((a, b) => a.getPriority().compareTo(b.getPriority()));

    final List<Note> notes = _turnItemsIntoNotes();
    debugPrint('Got ${notes.length} notes from items');
    final List<Note> widgetNotes = [];

    final checklists = _getChecklists();
    widgets = [...checklists, ...widgets];

    for (var widget in widgets) {
      try {
        widgetNotes.addAll(await widget.generateDashboardItems());
      } catch (e) {
        debugPrint('Error while generating widget notes: $e');
      }
    }
    debugPrint('Got ${widgetNotes.length} notes from widgets');
    widgetNotes.addAll(notes);

    // if there are more than 4 notes, only show the first 4
    if (widgetNotes.length > 4) {
      widgetNotes.removeRange(4, widgetNotes.length);
    }

    // set the note indexes to 1, 2, 3, 4
    for (var i = 0; i < widgetNotes.length; i++) {
      widgetNotes[i].noteNumber = i + 1;
    }

    return widgetNotes;
  }

  void _sortItemsByTime() {
    final now = DateTime.now();

    items.sort((a, b) {
      if (a.hour == null || a.minute == null) {
        return 1;
      }
      if (b.hour == null || b.minute == null) {
        return -1;
      }

      final aTime = DateTime(now.year, now.month, now.day, a.hour!, a.minute!);
      final bTime = DateTime(now.year, now.month, now.day, b.hour!, b.minute!);

      return aTime.compareTo(bTime);
    });
  }

  List<Note> _turnItemsIntoNotes() {
    final List<Note> notes = [];

    final now = DateTime.now();
    final futureItems = <DashboardItem>[];

    for (var fpi in items) {
      if (fpi.hour != null && fpi.minute != null) {
        final itemTime =
            DateTime(now.year, now.month, now.day, fpi.hour!, fpi.minute!);
        if (itemTime.isAfter(now)) {
          futureItems.add(fpi);
        }
      }
    }

    // devide into lists of 4
    final List<List<DashboardItem>> chunks = [];
    int chunkIndex = 0;
    for (var i = 0; i < futureItems.length; i++) {
      if (i % 4 == 0) {
        chunks.add([]);
        chunkIndex++;
      }
      chunks[chunkIndex - 1].add(futureItems[i]);
    }

    // generate notes for the first 4 chunks
    for (var i = 0; i < chunks.length && i < 4; i++) {
      final chunk = chunks[i];
      final note = Note(
        noteNumber: i + 1,
        name: 'G1 Extended',
        text: chunk.map((e) => e.toString()).join('\n'),
      );
      notes.add(note);
    }

    return notes;
  }
}
