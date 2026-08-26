import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/models/dashboard/dashboard_widget.dart';
import 'package:g1_extended/models/g1/note.dart';

/// One thing Home Assistant knows about.
class HaEntity {
  final String entityId;
  final String state;
  final String friendlyName;
  final String? unit;

  const HaEntity({
    required this.entityId,
    required this.state,
    required this.friendlyName,
    this.unit,
  });

  /// The domain part: `light`, `sensor`, `climate`…
  String get domain => entityId.split('.').first;

  /// What the lens should show: the value and its unit, nothing else.
  String get display => unit == null || unit!.isEmpty ? state : '$state$unit';

  static HaEntity? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['entity_id'];
    if (id is! String || !id.contains('.')) return null;

    final attributes = raw['attributes'];
    final name = attributes is Map ? attributes['friendly_name'] : null;
    final unit = attributes is Map ? attributes['unit_of_measurement'] : null;

    return HaEntity(
      entityId: id,
      state: raw['state'] as String? ?? 'unknown',
      friendlyName: name is String && name.isNotEmpty ? name : id,
      unit: unit is String ? unit : null,
    );
  }
}

/// What came back, said plainly.
sealed class HaResult {
  const HaResult();
}

class HaOk extends HaResult {
  final String text;
  const HaOk(this.text);
}

class HaFailure extends HaResult {
  final String reason;
  const HaFailure(this.reason);
}

/// Talks to a Home Assistant instance over its REST API.
///
/// Deliberately separate from [AssistantService]. That one speaks the
/// OpenAI chat shape and is about *asking a model something*; this one is
/// about a house — reading what a sensor says and telling a light to turn
/// off. The two can be pointed at the same Home Assistant and do different
/// jobs there, and conflating them would make it impossible to have an
/// assistant configured without also exposing the house, or the reverse.
///
/// Everything here is opt-in and off by default, and nothing polls in the
/// background: the lens cards are refreshed when the dashboard is built,
/// which is the same contract the weather and custom cards already keep.
class HomeAssistantService implements DashboardWidget {
  HomeAssistantService._internal();
  static final HomeAssistantService singleton = HomeAssistantService._internal();
  factory HomeAssistantService() => singleton;

  static const _enabledKey = 'home_assistant_enabled';
  static const _baseUrlKey = 'home_assistant_base_url';
  static const _entitiesKey = 'home_assistant_lens_entities';
  static const _tokenKey = 'home_assistant_token';

  /// The lens holds four notes in total, shared with everything else that
  /// wants one. Asking for more than a couple here is asking for the
  /// dashboard to drop them.
  static const int maxLensEntities = 4;

  /// A lens line has no room for a paragraph.
  static const int maxSpokenLength = 220;

  static const Duration timeout = Duration(seconds: 15);

  /// Below the weather and the calendar: the house is useful, not urgent.
  @override
  int getPriority() => 40;

  /// Overridable so tests need no network.
  @visibleForTesting
  static http.Client Function()? clientFactory;

  http.Client get _client => (clientFactory ?? http.Client.new)();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? '';
  }

  Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, value.trim());
  }

  /// The long-lived access token, in the keystore rather than beside the
  /// brightness setting: it opens the whole house.
  Future<String?> token() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (e) {
      debugPrint('HomeAssistantService: could not read the token: $e');
      return null;
    }
  }

  Future<void> setToken(String? value) async {
    try {
      if (value == null || value.trim().isEmpty) {
        await _secure.delete(key: _tokenKey);
      } else {
        await _secure.write(key: _tokenKey, value: value.trim());
      }
    } catch (e) {
      debugPrint('HomeAssistantService: could not store the token: $e');
    }
  }

  /// Which entities appear on the lens, in the order they were chosen.
  Future<List<String>> lensEntities() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_entitiesKey) ?? const [];
  }

  Future<void> setLensEntities(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _entitiesKey,
      ids.take(maxLensEntities).toList(),
    );
  }

  Future<bool> isConfigured() async {
    if (!await isEnabled()) return false;
    if (endpointFor(await baseUrl(), '/api/') == null) return false;
    final key = await token();
    return key != null && key.isNotEmpty;
  }

  /// Builds an absolute URL for a Home Assistant path.
  ///
  /// Tolerant about what someone types: a bare host, a trailing slash, or
  /// a full URL all resolve to the same place. Returns null when there is
  /// nothing usable, so callers can refuse rather than guess.
  @visibleForTesting
  static Uri? endpointFor(String base, String path) {
    var text = base.trim();
    if (text.isEmpty) return null;

    if (!text.contains('://')) text = 'http://$text';
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }

    // Someone who pasted the address bar of their dashboard.
    for (final suffix in const ['/lovelace', '/config', '/api']) {
      if (text.endsWith(suffix)) {
        text = text.substring(0, text.length - suffix.length);
      }
    }

    final uri = Uri.tryParse('$text$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  Future<Map<String, String>> _headers() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await token() ?? ''}',
      };

  /// Checks the address and the token together, because a person getting
  /// this working needs to know which of the two is wrong.
  Future<HaResult> ping() async {
    final url = endpointFor(await baseUrl(), '/api/');
    if (url == null) return const HaFailure('That address is not usable.');

    final key = await token();
    if (key == null || key.isEmpty) {
      return const HaFailure('No access token yet.');
    }

    final client = _client;
    try {
      final response =
          await client.get(url, headers: await _headers()).timeout(timeout);

      return switch (response.statusCode) {
        200 => const HaOk('Home Assistant answered.'),
        401 => const HaFailure('The token was refused. Make a new long-lived '
            'access token in your Home Assistant profile.'),
        404 => const HaFailure('Reached the server, but not the API. Check '
            'the address ends at the base of Home Assistant.'),
        _ => HaFailure('Home Assistant answered ${response.statusCode}.'),
      };
    } on TimeoutException {
      return const HaFailure('No answer within 15 seconds.');
    } catch (e) {
      debugPrint('HomeAssistantService: ping failed: $e');
      return const HaFailure('Could not reach that address.');
    } finally {
      client.close();
    }
  }

  /// Puts a sentence to Home Assistant's own conversation agent.
  ///
  /// This is the path that makes the glasses speak to the house: whatever
  /// agent is configured over there — the built-in one, or a model — is
  /// what answers, so the phone needs no intent parsing of its own.
  Future<HaResult> converse(String sentence) async {
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return const HaFailure('Nothing to say.');

    final url = endpointFor(await baseUrl(), '/api/conversation/process');
    if (url == null) return const HaFailure('That address is not usable.');

    final client = _client;
    try {
      final response = await client
          .post(
            url,
            headers: await _headers(),
            body: jsonEncode({'text': trimmed, 'language': 'en'}),
          )
          .timeout(timeout);

      if (response.statusCode == 401) {
        return const HaFailure('The token was refused.');
      }
      if (response.statusCode != 200) {
        return HaFailure('Home Assistant answered ${response.statusCode}.');
      }

      final spoken = speechFrom(response.body);
      if (spoken == null || spoken.isEmpty) {
        return const HaFailure('Home Assistant had nothing to say.');
      }
      return HaOk(spoken);
    } on TimeoutException {
      return const HaFailure('Home Assistant did not answer in time.');
    } catch (e) {
      debugPrint('HomeAssistantService: converse failed: $e');
      return const HaFailure('Could not reach Home Assistant.');
    } finally {
      client.close();
    }
  }

  /// Digs the spoken reply out of a conversation response.
  ///
  /// The shape is nested deeply enough that reading it inline at the call
  /// site would hide a mistake; every level is checked rather than cast.
  @visibleForTesting
  static String? speechFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      final response = decoded['response'];
      if (response is! Map) return null;

      final speech = response['speech'];
      if (speech is! Map) return null;

      final plain = speech['plain'];
      if (plain is! Map) return null;

      final text = plain['speech'];
      if (text is! String) return null;

      return shorten(text);
    } catch (e) {
      debugPrint('HomeAssistantService: unreadable answer: $e');
      return null;
    }
  }

  /// Trims an answer to something a lens line can hold.
  ///
  /// Cut on a sentence boundary when there is one near the end, so the
  /// wearer reads a finished thought rather than half a clause.
  @visibleForTesting
  static String shorten(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxSpokenLength) return collapsed;

    final clipped = collapsed.substring(0, maxSpokenLength);
    final stop = clipped.lastIndexOf(RegExp(r'[.!?]'));
    if (stop > maxSpokenLength ~/ 2) return clipped.substring(0, stop + 1);
    return '${clipped.trimRight()}…';
  }

  /// Everything Home Assistant will tell us about, for the picker.
  Future<List<HaEntity>> states() async {
    final url = endpointFor(await baseUrl(), '/api/states');
    if (url == null) return const [];

    final client = _client;
    try {
      final response =
          await client.get(url, headers: await _headers()).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('HomeAssistantService: states gave ${response.statusCode}');
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final entities = <HaEntity>[];
      for (final raw in decoded) {
        final entity = HaEntity.fromMap(raw);
        if (entity != null) entities.add(entity);
      }

      entities.sort((a, b) => a.friendlyName
          .toLowerCase()
          .compareTo(b.friendlyName.toLowerCase()));
      return entities;
    } on TimeoutException {
      debugPrint('HomeAssistantService: states timed out');
      return const [];
    } catch (e) {
      debugPrint('HomeAssistantService: states failed: $e');
      return const [];
    } finally {
      client.close();
    }
  }

  Future<HaEntity?> entity(String entityId) async {
    final url = endpointFor(await baseUrl(), '/api/states/$entityId');
    if (url == null) return null;

    final client = _client;
    try {
      final response =
          await client.get(url, headers: await _headers()).timeout(timeout);
      if (response.statusCode != 200) return null;
      return HaEntity.fromMap(jsonDecode(response.body));
    } catch (e) {
      debugPrint('HomeAssistantService: could not read $entityId: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// The chosen entities as lens notes.
  ///
  /// Fetched only when the dashboard is being built. An entity that cannot
  /// be read is left out rather than shown as an error: a card that says
  /// `--` where a temperature should be is worse than no card, because it
  /// looks like the house answered.
  @override
  Future<List<Note>> generateDashboardItems() async {
    if (!await isConfigured()) return const [];

    final chosen = await lensEntities();
    if (chosen.isEmpty) return const [];

    final notes = <Note>[];
    for (final id in chosen.take(maxLensEntities)) {
      final entity = await this.entity(id);
      if (entity == null) continue;

      notes.add(Note(
        // Renumbered by the dashboard once everything is collected.
        noteNumber: 1,
        name: entity.friendlyName,
        text: entity.display,
      ));
    }
    return notes;
  }
}
