import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the app knows about you, in one file, and back.
///
/// Insurance, not a feature. Android sometimes refuses to install one build
/// over another — a debug signature met a release one, or an architecture
/// changed — and the only way through is uninstalling, which takes the
/// notes, the cards, the exclusion lists and every preference with it.
/// After the second time that happens to someone testing betas, an app
/// without export is an app that punishes its testers.
///
/// One JSON document, readable in any editor — being able to see what a
/// backup holds is part of trusting it. Secrets stay out: the assistant's
/// API key lives in the platform keystore precisely so it cannot wander
/// into a file that gets pasted somewhere.
class SettingsBackup {
  const SettingsBackup._();

  /// Format version, bumped only when an old restore could misread.
  static const int version = 1;

  /// Preference keys that never travel.
  ///
  /// Diagnostics consent is a decision about *this* phone at *this*
  /// moment; carrying it silently to another install would turn one yes
  /// into a permanent one.
  static const List<String> _keptBack = [
    'action_journal_enabled',
    'action_journal_enabled_at',
    'diagnostics_redact',
  ];

  /// Hive boxes worth carrying: user content and user filters.
  static const List<String> _plainBoxes = [
    'customCards',
    'notificationBlocklist',
    'extensions',
    'appPrefs',
  ];

  /// App-document files that are user data rather than diagnostics.
  /// Captures and journals stay: they describe a phone, not a person's
  /// configuration, and they are the kind of thing best left behind.
  static const List<String> _files = [
    'notes.json',
    'notification-apps.json',
  ];

  static Future<Map<String, Object?>> _gather() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final preferences = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (_keptBack.contains(key)) continue;
      preferences[key] = prefs.get(key);
    }

    final boxes = <String, Map<String, Object?>>{};
    for (final name in _plainBoxes) {
      try {
        final box =
            Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
        final content = <String, Object?>{};
        for (final key in box.keys) {
          final value = box.get(key);
          // Only JSON-safe shapes travel; typed adapters would need their
          // own format and none of the carried boxes uses one.
          if (value is Map || value is List || value is String ||
              value is num || value is bool) {
            content['$key'] = value is Map
                ? Map<String, Object?>.from(value)
                : value;
          }
        }
        boxes[name] = content;
      } catch (e) {
        debugPrint('SettingsBackup: skipping box $name: $e');
      }
    }

    final files = <String, Object?>{};
    final dir = await getApplicationDocumentsDirectory();
    for (final name in _files) {
      try {
        final file = File('${dir.path}/$name');
        if (await file.exists()) {
          files[name] = jsonDecode(await file.readAsString());
        }
      } catch (e) {
        debugPrint('SettingsBackup: skipping file $name: $e');
      }
    }

    return {
      'what': 'G1 Extended settings backup',
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': preferences,
      'boxes': boxes,
      'files': files,
    };
  }

  /// The backup as pretty JSON, for the clipboard or a file.
  static Future<String> export() async =>
      const JsonEncoder.withIndent('  ').convert(await _gather());

  /// Restores a backup. Returns a short human summary, or throws
  /// [FormatException] with a reason a person can act on.
  static Future<String> restore(String source) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const FormatException('That is not JSON.');
    }
    if (decoded is! Map || decoded['what'] != 'G1 Extended settings backup') {
      throw const FormatException(
          'That JSON is not a G1 Extended backup — the header is missing.');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException(
          'This backup is from a newer app (format $fileVersion); '
          'update first, then restore.');
    }

    var restored = 0;

    final preferences = decoded['preferences'];
    if (preferences is Map) {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in preferences.entries) {
        final key = entry.key as String;
        if (_keptBack.contains(key)) continue;
        final value = entry.value;
        if (value is bool) await prefs.setBool(key, value);
        if (value is int) await prefs.setInt(key, value);
        if (value is double) await prefs.setDouble(key, value);
        if (value is String) await prefs.setString(key, value);
        restored++;
      }
    }

    final boxes = decoded['boxes'];
    if (boxes is Map) {
      for (final name in _plainBoxes) {
        final content = boxes[name];
        if (content is! Map) continue;
        try {
          final box =
              Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
          for (final entry in content.entries) {
            await box.put(entry.key, entry.value);
            restored++;
          }
        } catch (e) {
          debugPrint('SettingsBackup: could not restore box $name: $e');
        }
      }
    }

    final files = decoded['files'];
    if (files is Map) {
      final dir = await getApplicationDocumentsDirectory();
      for (final name in _files) {
        final content = files[name];
        if (content == null) continue;
        try {
          final file = File('${dir.path}/$name.restoring');
          await file.writeAsString(jsonEncode(content), flush: true);
          await file.rename('${dir.path}/$name');
          restored++;
        } catch (e) {
          debugPrint('SettingsBackup: could not restore file $name: $e');
        }
      }
    }

    return '$restored item(s) restored. Restart the app so everything '
        'rereads its settings.';
  }
}
