import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'package:g1_extended/models/dashboard/calendar.dart';

/// Which of the phone's calendars reach the glasses.
///
/// Everything flows by default and this screen holds the exclusions — the
/// same shape as the notification blocklist. The opposite arrangement was
/// tried and was the bug: an allowlist seeded only by opening this screen
/// meant a fresh install had an empty agenda forever, permission granted or
/// not, until someone found a page nothing pointed at.
class CalendarsPage extends StatefulWidget {
  const CalendarsPage({super.key});

  @override
  CalendarsPageState createState() => CalendarsPageState();
}

class CalendarsPageState extends State<CalendarsPage> {
  final List<Calendar> _calendars = [];
  late Box<DashboardCalendar> _calendarBox;

  bool _loading = true;
  bool _accessGranted = true;

  @override
  void initState() {
    super.initState();
    _calendarBox = Hive.box<DashboardCalendar>('calendarBox');
    _retrieveCalendars();
  }

  Future<void> _retrieveCalendars({bool ask = false}) async {
    setState(() => _loading = true);
    final plugin = DeviceCalendarPlugin();

    try {
      var access = (await plugin.hasPermissions()).data == true;

      // Asking is the button's job, not the screen's. A permission dialog
      // that appears merely because a page opened is how people learn to
      // tap "deny" without reading.
      if (!access && ask) {
        access = (await plugin.requestPermissions()).data == true;
      }

      if (!access) {
        if (mounted) {
          setState(() {
            _accessGranted = false;
            _loading = false;
          });
        }
        return;
      }

      final result = await plugin.retrieveCalendars();
      if (!mounted) return;

      setState(() {
        _accessGranted = true;
        _loading = false;
        _calendars
          ..clear()
          ..addAll(result.data ?? const <Calendar>[]);
      });
    } on PlatformException catch (e) {
      debugPrint('CalendarsPage: could not read the calendars: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isEnabled(Calendar calendar) => _calendarBox.values
      .firstWhere(
        (c) => c.id == calendar.id,
        // Absent from the box means included.
        orElse: () => DashboardCalendar(id: calendar.id!, enabled: true),
      )
      .enabled;

  Future<void> _toggle(Calendar calendar) async {
    final stored = _calendarBox.values.toList();
    final index = stored.indexWhere((c) => c.id == calendar.id);

    if (index == -1) {
      // Untouched means included, so a first toggle is an exclusion.
      await _calendarBox.add(
        DashboardCalendar(id: calendar.id!, enabled: false),
      );
    } else {
      final entry = stored[index];
      entry.enabled = !entry.enabled;
      await _calendarBox.putAt(index, entry);
    }

    if (mounted) setState(() {});
  }

  /// Grouped the way the accounts themselves are, which is how the phone's
  /// own settings present them and how anyone with five Google accounts
  /// finds the right one.
  Map<String, List<Calendar>> get _byAccount {
    final grouped = <String, List<Calendar>>{};
    for (final calendar in _calendars) {
      final account = (calendar.accountName ?? '').trim();
      grouped.putIfAbsent(account.isEmpty ? 'This device' : account, () => [])
          .add(calendar);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final included = _calendars.where(_isEnabled).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendars'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Look again',
            onPressed: () => _retrieveCalendars(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_accessGranted
              ? _NoAccess(onAsk: () => _retrieveCalendars(ask: true))
              : _calendars.isEmpty
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Text(
                            '$included of ${_calendars.length} calendars reach '
                            'the glasses. Everything is included until you '
                            'turn it off here.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        for (final entry in _byAccount.entries) ...[
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final calendar in entry.value)
                            SwitchListTile(
                              value: _isEnabled(calendar),
                              title: Text(calendar.name ?? 'Unnamed'),
                              subtitle: calendar.isReadOnly == true
                                  ? const Text('Read only')
                                  : null,
                              onChanged: (_) => _toggle(calendar),
                            ),
                        ],
                      ],
                    ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onAsk});

  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The app cannot read your calendars yet.\n\n'
                'Android asks for read and write together, though nothing '
                'here ever creates or changes an event.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onAsk, child: const Text('Allow')),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No calendars on this phone.\n\n'
            'Accounts synced in the phone\'s own Calendar app appear here; '
            'if yours is missing, it is likely not syncing to the device.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
