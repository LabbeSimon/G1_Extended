import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:g1_extended/models/g1/note_slots.dart';

/// One extra clock on the lens.
class WorldClock {
  const WorldClock({required this.label, required this.zoneId});

  /// What the wearer calls it — "Tokyo", "Maman", "Bureau NY".
  final String label;

  /// IANA zone name, "Asia/Tokyo". Never a fixed offset: an offset is wrong
  /// twice a year, silently, in exactly the way nothing in this app is
  /// allowed to be.
  final String zoneId;

  Map<String, String> toMap() => {'label': label, 'zone': zoneId};

  static WorldClock? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'] as String?;
    final zone = raw['zone'] as String?;
    if (label == null || zone == null) return null;
    return WorldClock(label: label, zoneId: zone);
  }
}

/// The extra time zones shown on the glasses.
///
/// They ride in a note slot, composed alongside the dashboard's own items:
/// the lens already shows local time in its header, so this holds only the
/// elsewhere.
class WorldClocksService {
  WorldClocksService._internal();
  static final WorldClocksService singleton = WorldClocksService._internal();
  factory WorldClocksService() => singleton;

  static const String _key = 'world_clocks';

  /// The lens gives a note roughly four usable lines.
  static const int maxClocks = 4;

  bool _tzReady = false;

  /// Cities offered by the picker. Deliberately short: a search box over
  /// four hundred IANA names is a chore, and these cover the zones people
  /// actually mean. The stored value is always the IANA id, so anything can
  /// be added by a later version without migrating anyone.
  static const Map<String, String> suggestions = {
    'Paris': 'Europe/Paris',
    'London': 'Europe/London',
    'Lisbon': 'Europe/Lisbon',
    'Berlin': 'Europe/Berlin',
    'Athens': 'Europe/Athens',
    'Moscow': 'Europe/Moscow',
    'Dubai': 'Asia/Dubai',
    'Mumbai': 'Asia/Kolkata',
    'Bangkok': 'Asia/Bangkok',
    'Singapore': 'Asia/Singapore',
    'Hong Kong': 'Asia/Hong_Kong',
    'Shanghai': 'Asia/Shanghai',
    'Tokyo': 'Asia/Tokyo',
    'Seoul': 'Asia/Seoul',
    'Sydney': 'Australia/Sydney',
    'Auckland': 'Pacific/Auckland',
    'New York': 'America/New_York',
    'Chicago': 'America/Chicago',
    'Denver': 'America/Denver',
    'Los Angeles': 'America/Los_Angeles',
    'Mexico City': 'America/Mexico_City',
    'São Paulo': 'America/Sao_Paulo',
    'Montréal': 'America/Toronto',
    'Réunion': 'Indian/Reunion',
    'Nouméa': 'Pacific/Noumea',
    'Papeete': 'Pacific/Tahiti',
    'Pointe-à-Pitre': 'America/Guadeloupe',
    'Cayenne': 'America/Cayenne',
  };

  void _ensureTz() {
    if (_tzReady) return;
    // ~100 ms once, paid on first use rather than at every launch by the
    // majority who never add a clock.
    tzdata.initializeTimeZones();
    _tzReady = true;
  }

  Future<List<WorldClock>> clocks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final list = jsonDecode(raw) as List;
      return list.map(WorldClock.fromMap).whereType<WorldClock>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<WorldClock> clocks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final c in clocks.take(maxClocks)) c.toMap()]),
    );
  }

  /// The note as it should appear on the lens, or null when no clock is set.
  Future<SlotContent?> slotContent({DateTime? now}) async {
    final configured = await clocks();
    if (configured.isEmpty) return null;

    _ensureTz();
    final local = now ?? DateTime.now();

    final lines = <String>[];
    for (final clock in configured.take(maxClocks)) {
      final line = formatLine(clock, local);
      if (line != null) lines.add(line);
    }
    if (lines.isEmpty) return null;

    return SlotContent(name: 'Clocks', text: lines.join('\n'));
  }

  /// "Tokyo 21:32", with "+1" or "-1" appended when it is already tomorrow
  /// or still yesterday there — the difference that actually surprises
  /// people, and the one a bare time hides.
  static String? formatLine(WorldClock clock, DateTime localNow) {
    final tz.Location location;
    try {
      location = tz.getLocation(clock.zoneId);
    } catch (_) {
      // A zone the database no longer knows. Skipping the line is better
      // than showing a time that means nothing.
      return null;
    }

    final there = tz.TZDateTime.from(localNow, location);
    final hh = there.hour.toString().padLeft(2, '0');
    final mm = there.minute.toString().padLeft(2, '0');

    final dayShift = DateTime(there.year, there.month, there.day)
        .difference(DateTime(localNow.year, localNow.month, localNow.day))
        .inDays;
    final marker = dayShift == 0 ? '' : (dayShift > 0 ? ' +1' : ' -1');

    return '${clock.label} $hh:$mm$marker';
  }
}
