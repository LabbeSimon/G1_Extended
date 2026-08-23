import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A release newer than the one running.
class AvailableUpdate {
  final String version;
  final String url;
  final String? notes;

  /// Direct download for the APK asset, when the release carries one.
  final String? apkUrl;

  /// Its size in bytes, for the progress bar. Zero when unknown.
  final int apkBytes;

  const AvailableUpdate({
    required this.version,
    required this.url,
    this.notes,
    this.apkUrl,
    this.apkBytes = 0,
  });
}

/// Checks whether a newer release exists on GitHub.
///
/// The app is distributed as an APK outside any store, so nothing else would
/// ever tell the user an update exists. The check is a plain unauthenticated
/// GET against a public endpoint: no account, no identifier, no telemetry, and
/// it can be turned off. It never downloads or installs anything by itself —
/// it opens the release page and lets the user decide.
class UpdateService {
  UpdateService._internal();
  static final UpdateService singleton = UpdateService._internal();
  factory UpdateService() => singleton;

  static const String _latestUrl =
      'https://api.github.com/repos/LabbeSimon/G1_Extended/releases/latest';

  /// All releases, newest first — the only way to see pre-releases, which
  /// GitHub deliberately keeps out of /releases/latest.
  static const String _allReleasesUrl =
      'https://api.github.com/repos/LabbeSimon/G1_Extended/releases?per_page=20';

  static const String _betaKey = 'update_channel_beta';

  static const String _enabledKey = 'update_check_enabled';
  static const String _lastCheckKey = 'update_check_last';
  static const String _skippedKey = 'update_check_skipped_version';

  /// Checking more often than this is pointless and rude to the API.
  static const Duration minimumInterval = Duration(hours: 12);

  /// Whether this install follows the beta channel.
  ///
  /// Off by default, and deliberately not a switch anyone trips over:
  /// pre-releases carry work that has compiled and passed its tests but
  /// has not been worn on a face, and half this codebase talks to hardware
  /// over Bluetooth. Someone who turns this on is volunteering.
  Future<bool> isBeta() async =>
      (await SharedPreferences.getInstance()).getBool(_betaKey) ?? false;

  Future<void> setBeta(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_betaKey, enabled);
    // The skipped-version memory belongs to the old channel; keeping it
    // would hide the first release of the new one.
    await prefs.remove(_skippedKey);
    await prefs.remove(_lastCheckKey);
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// The version the user chose to ignore, so we stop nagging about it.
  Future<void> skip(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedKey, version);
  }

  /// Returns an update worth showing, or null.
  ///
  /// Pass [force] when the user asked explicitly, which bypasses both the
  /// interval and the skipped-version memory.
  Future<AvailableUpdate?> check({bool force = false}) async {
    if (!force && !await isEnabled()) return null;

    final prefs = await SharedPreferences.getInstance();

    if (!force) {
      final last = prefs.getInt(_lastCheckKey);
      if (last != null) {
        final since = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        );
        if (since < minimumInterval) return null;
      }
    }

    final release = await _fetchLatest();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    if (release == null) return null;

    final current = (await PackageInfo.fromPlatform()).version;
    if (!isNewer(release.version, current)) return null;

    if (!force && prefs.getString(_skippedKey) == release.version) return null;

    return release;
  }

  Future<AvailableUpdate?> _fetchLatest() async {
    final beta = await isBeta();
    try {
      final response = await http
          .get(Uri.parse(beta ? _allReleasesUrl : _latestUrl),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('UpdateService: releases endpoint returned '
            '${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);

      // On the stable channel GitHub hands back the one release; on beta it
      // hands back the list, and the newest usable entry has to be picked
      // out of it — skipping drafts, which are not published to anybody.
      final Map<String, dynamic>? json = decoded is List
          ? pickNewestRelease(decoded)
          : (decoded as Map<String, dynamic>);
      if (json == null) return null;

      final tag = json['tag_name'] as String?;
      final url = json['html_url'] as String?;
      if (tag == null || url == null) return null;

      final notes = (json['body'] as String?)?.trim();
      final apk = pickApkAsset(json);

      return AvailableUpdate(
        version: normalise(tag),
        url: url,
        notes: notes == null || notes.isEmpty ? null : notes,
        apkUrl: apk?.$1,
        apkBytes: apk?.$2 ?? 0,
      );
    } catch (e) {
      debugPrint('UpdateService: check failed: $e');
      return null;
    }
  }

  /// The newest release in a listing, drafts excluded.
  ///
  /// GitHub orders the list newest-first by creation, which is not quite
  /// the same as by version — a patch cut after a later beta would sort
  /// ahead of it. So versions are compared rather than trusted to order.
  @visibleForTesting
  static Map<String, dynamic>? pickNewestRelease(List<dynamic> releases) {
    Map<String, dynamic>? best;
    for (final raw in releases) {
      if (raw is! Map) continue;
      final release = Map<String, dynamic>.from(raw);
      if (release['draft'] == true) continue;
      final tag = release['tag_name'] as String?;
      if (tag == null) continue;

      if (best == null ||
          isNewer(normalise(tag), normalise(best['tag_name'] as String))) {
        best = release;
      }
    }
    return best;
  }

  /// The APK among a release's assets, as (url, size).
  ///
  /// By suffix, not by exact name: the asset is named after the tag, and
  /// tying this to today's naming would quietly break the update button the
  /// day the naming changes.
  @visibleForTesting
  static (String, int)? pickApkAsset(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return null;

    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String?;
      if (url == null || !name.toLowerCase().endsWith('.apk')) continue;
      return (url, (asset['size'] as num?)?.toInt() ?? 0);
    }
    return null;
  }

  /// Downloads the update's APK into the cache, reporting progress 0..1.
  ///
  /// The cache directory on purpose: Android may clear it whenever it
  /// likes, which is exactly right for a file that is disposable the moment
  /// it is installed. Anything older is deleted first, so failed attempts
  /// do not pile up.
  Future<File?> downloadApk(
    AvailableUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final apkUrl = update.apkUrl;
    if (apkUrl == null) return null;

    final client = http.Client();
    try {
      final dir = await getApplicationCacheDirectory();
      final target = File('${dir.path}/update-${update.version}.apk');

      await for (final stale in dir.list()) {
        final name = stale.path.split('/').last;
        if (name.startsWith('update-') && name.endsWith('.apk')) {
          await stale.delete();
        }
      }

      final response =
          await client.send(http.Request('GET', Uri.parse(apkUrl)));
      if (response.statusCode != 200) {
        debugPrint('UpdateService: download returned ${response.statusCode}');
        return null;
      }

      final total = response.contentLength ?? update.apkBytes;
      final sink = target.openWrite();
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }

      // A partial file handed to the installer produces a parse error with
      // no explanation; better to say the download failed.
      if (total > 0 && received < total) {
        await target.delete();
        return null;
      }

      return target;
    } catch (e) {
      debugPrint('UpdateService: download failed: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Strips the leading "v" that release tags conventionally carry.
  @visibleForTesting
  static String normalise(String tag) =>
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;

  /// True when [candidate] is a later version than [current].
  ///
  /// Numeric segment by segment, so 1.0.10 beats 1.0.9 where a string
  /// comparison gets it backwards. Missing segments count as zero and the
  /// build metadata after "+" is ignored, as it identifies a build rather
  /// than a version.
  ///
  /// The pre-release suffix after "-" is *not* ignored, and that matters:
  /// it used to be, which made 1.1.2-beta.6 and 1.1.2 equal — so the beta
  /// channel would have compared every pre-release against the running
  /// version, found them equal, and offered nothing at all, silently and
  /// forever. Semantic versioning's rule applies: a pre-release sorts
  /// before the release it leads to, and pre-releases sort among themselves
  /// part by part, numbers numerically.
  @visibleForTesting
  static bool isNewer(String candidate, String current) {
    final a = _segments(candidate);
    final b = _segments(current);
    if (a.isEmpty) return false;

    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }

    // Same numbers: the pre-release decides.
    return _comparePreRelease(
          _preRelease(candidate),
          _preRelease(current),
        ) >
        0;
  }

  /// Everything between "-" and any "+", or empty for a plain release.
  static String _preRelease(String version) {
    final core = normalise(version.trim()).split('+').first;
    final dash = core.indexOf('-');
    return dash == -1 ? '' : core.substring(dash + 1);
  }

  /// Semantic versioning's ordering: absent beats present — 1.1.2 is later
  /// than 1.1.2-beta.6 — and otherwise part by part, numbers numerically so
  /// beta.10 follows beta.9 rather than preceding it.
  static int _comparePreRelease(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;

    final left = a.split('.');
    final right = b.split('.');

    for (var i = 0; i < (left.length > right.length ? left.length : right.length); i++) {
      if (i >= left.length) return -1;
      if (i >= right.length) return 1;

      final l = int.tryParse(left[i]);
      final r = int.tryParse(right[i]);

      if (l != null && r != null) {
        if (l != r) return l > r ? 1 : -1;
      } else if (l != null) {
        // Numeric parts have lower precedence than alphanumeric ones.
        return -1;
      } else if (r != null) {
        return 1;
      } else {
        final c = left[i].compareTo(right[i]);
        if (c != 0) return c > 0 ? 1 : -1;
      }
    }
    return 0;
  }

  static List<int> _segments(String version) {
    final core = normalise(version.trim()).split(RegExp(r'[+\-]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList();
  }
}
