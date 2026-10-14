import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:g1_extended/models/dashboard/dashboard_widget.dart';
import 'package:g1_extended/models/g1/note.dart';
import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/heart_rate_service.dart';
import 'package:g1_extended/services/card_template.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';
import 'package:g1_extended/services/speedometer_service.dart';
import 'package:g1_extended/utils/ui_perfs.dart';

/// A line of the wearer's own making, shown on the glasses.
class CustomCard {
  final String id;
  final String title;
  final String template;
  final bool enabled;

  /// Optional URL polled for the `{value}` token.
  final String? sourceUrl;

  /// Dotted path into a JSON reply, empty for plain text.
  final String? sourcePath;

  /// Minutes between fetches. Never below one.
  final int refreshMinutes;

  const CustomCard({
    required this.id,
    required this.title,
    required this.template,
    this.enabled = true,
    this.sourceUrl,
    this.sourcePath,
    this.refreshMinutes = 15,
  });

  bool get hasSource => (sourceUrl ?? '').trim().isNotEmpty;

  CustomCard copyWith({
    String? title,
    String? template,
    bool? enabled,
    String? sourceUrl,
    String? sourcePath,
    int? refreshMinutes,
  }) =>
      CustomCard(
        id: id,
        title: title ?? this.title,
        template: template ?? this.template,
        enabled: enabled ?? this.enabled,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        sourcePath: sourcePath ?? this.sourcePath,
        refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'template': template,
        'enabled': enabled,
        'sourceUrl': sourceUrl,
        'sourcePath': sourcePath,
        'refreshMinutes': refreshMinutes,
      };

  static CustomCard fromMap(Map map) => CustomCard(
        id: map['id'] as String? ?? const Uuid().v4(),
        title: map['title'] as String? ?? '',
        template: map['template'] as String? ?? '',
        enabled: map['enabled'] as bool? ?? true,
        sourceUrl: map['sourceUrl'] as String?,
        sourcePath: map['sourcePath'] as String?,
        refreshMinutes: map['refreshMinutes'] as int? ?? 15,
      );
}

/// Lets the wearer put their own information on the glasses.
///
/// The firmware draws the panes and decides how they look; what it does not
/// decide is what the four note slots say. That is the opening, and this is
/// what goes through it: lines the user writes, with `{time}`, `{battery}` or
/// a value pulled from a URL of their choosing dropped in.
///
/// The fetching deserves a word. Every other request this app makes is one the
/// app chose; these are the user's own, to hosts only they know about. They
/// are off unless a card asks for one, never made more often than the card
/// says, and listed plainly in the editor.
class CustomCardsService implements DashboardWidget {
  CustomCardsService._internal();
  static final CustomCardsService singleton = CustomCardsService._internal();
  factory CustomCardsService() => singleton;

  /// The hardware shows four notes, and the calendar and checklists want
  /// some of them, so custom cards are capped below that.
  static const int maxCards = 4;

  static const String _boxName = 'customCards';

  /// Shown before anything the user's own widgets provide.
  @override
  int getPriority() => 50;

  final Map<String, _CachedValue> _fetched = {};

  Future<List<CustomCard>> all() async {
    final box = await _openBox();
    return box.values
        .whereType<Map>()
        .map(CustomCard.fromMap)
        .toList();
  }

  Future<List<CustomCard>> enabled() async =>
      (await all()).where((card) => card.enabled).take(maxCards).toList();

  Future<void> save(CustomCard card) async {
    final box = await _openBox();
    await box.put(card.id, card.toMap());
    _fetched.remove(card.id);
  }

  Future<void> delete(String id) async {
    final box = await _openBox();
    await box.delete(id);
    _fetched.remove(id);
  }

  static CustomCard blank() => CustomCard(
        id: const Uuid().v4(),
        title: 'New card',
        template: '{time}  ·  {battery}',
      );

  @override
  Future<List<Note>> generateDashboardItems() async {
    final cards = await enabled();
    if (cards.isEmpty) return const [];

    final values = await _liveValues();
    final notes = <Note>[];

    for (final card in cards) {
      final resolved = Map<String, String?>.from(values);
      if (card.hasSource) {
        resolved['value'] = await _valueFor(card);
      }

      final text = CardTemplate.render(card.template, resolved).trim();
      if (text.isEmpty) continue;

      notes.add(Note(
        // Renumbered by the dashboard once everything is collected.
        noteNumber: 1,
        name: card.title,
        text: text,
      ));
    }

    return notes;
  }

  /// Renders a card without touching the network, for the live preview.
  Future<String> preview(CustomCard card) async {
    final values = await _liveValues();
    if (card.hasSource) {
      values['value'] = _fetched[card.id]?.value ?? '…';
    }
    return CardTemplate.render(card.template, values);
  }

  Future<Map<String, String?>> _liveValues() async {
    final now = DateTime.now();
    final battery = BluetoothManager.singleton.batteryStatus;

    String? weather;
    String? temperature;
    try {
      final reading = await OpenMeteoWeatherService().getCurrentWeather();
      if (reading != null) {
        temperature = '${reading.temperature.round()}°';
        weather = reading.description;
      }
    } catch (e) {
      debugPrint('CustomCardsService: no weather available: $e');
    }

    return {
      'time': CardTemplate.formatTime(
        now,
        twentyFourHour:
            UiPerfs.singleton.timeFormat == TimeFormat.TWENTY_FOUR_HOUR,
      ),
      'date': CardTemplate.formatDate(now),
      'day': CardTemplate.formatDay(now),
      'battery': battery.lowestBatteryPercentage == null
          ? null
          : '${battery.lowestBatteryPercentage}%',
      // Only a fresh reading; the service returns null past fifteen
      // seconds, and the renderer shows the dash — an old heart rate is a
      // lie with a confident face, worse on a lens than absence.
      'hr': HeartRateService.singleton.current == null
          ? null
          : '${HeartRateService.singleton.current!.bpm}',
      'battery_left': battery.leftBattery == null
          ? null
          : '${battery.leftBattery!.percentage}%',
      'battery_right': battery.rightBattery == null
          ? null
          : '${battery.rightBattery!.percentage}%',
      'temp': temperature,
      'weather': weather,
      'speed': SpeedometerService.singleton.label,
      'next_event': null,
    };
  }

  /// Fetches a card's source, no more often than the card asked for.
  Future<String?> _valueFor(CustomCard card) async {
    final cached = _fetched[card.id];
    final interval = Duration(minutes: card.refreshMinutes.clamp(1, 1440));

    if (cached != null &&
        DateTime.now().difference(cached.at) < interval) {
      return cached.value;
    }

    final value = await fetch(card);
    _fetched[card.id] = _CachedValue(value, DateTime.now());
    return value;
  }

  /// Performs the request. Public so the editor can offer a test button:
  /// nobody should have to wait for a refresh to find out their URL is wrong.
  Future<String?> fetch(CustomCard card) async {
    final url = card.sourceUrl?.trim();
    if (url == null || url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.isScheme('https')) {
      debugPrint('CustomCardsService: refusing a non-https source');
      return null;
    }

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('CustomCardsService: ${card.title} returned '
            '${response.statusCode}');
        return null;
      }

      final body = response.body;
      final path = card.sourcePath?.trim() ?? '';

      if (path.isEmpty) return CardSource.clamp(body);

      try {
        return CardSource.extract(jsonDecode(body), path);
      } on FormatException {
        debugPrint('CustomCardsService: ${card.title} is not JSON');
        return CardSource.clamp(body);
      }
    } catch (e) {
      debugPrint('CustomCardsService: ${card.title} failed: $e');
      return null;
    }
  }

  Future<Box> _openBox() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);
}

class _CachedValue {
  final String? value;
  final DateTime at;

  const _CachedValue(this.value, this.at);
}
