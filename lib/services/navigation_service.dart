import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';

import 'package:g1_extended/services/navigation_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/speedometer_service.dart';

/// Puts turn-by-turn directions on the glasses by reading the notification the
/// navigation app already posts.
///
/// There is no API for this and there does not need to be one: while it is
/// guiding you, Google Maps keeps an ongoing notification whose title is the
/// manoeuvre and whose text is the road. Reading it costs nothing, works with
/// whatever app the user prefers, and stops the moment they stop navigating.
///
/// The whole difficulty is restraint. That notification is rewritten several
/// times a second as the distance counts down, and the glasses cannot be
/// redrawn at that rate — so only a genuine change of instruction is sent.
class NavigationService {
  NavigationService._internal();
  static final NavigationService singleton = NavigationService._internal();
  factory NavigationService() => singleton;

  /// Apps whose ongoing notification is a turn instruction.
  static const Map<String, String> supportedApps = {
    'com.google.android.apps.maps': 'Google Maps',
    'com.waze': 'Waze',
    'com.organicmaps.app': 'Organic Maps',
    'net.osmand': 'OsmAnd',
    'net.osmand.plus': 'OsmAnd+',
    'com.mapbox.navigation': 'Mapbox',
  };

  static const String _enabledKey = 'navigation_enabled';

  /// Redrawing the lens faster than this is unreadable and drains the battery.
  static const Duration _minimumInterval = Duration(seconds: 2);

  /// Directions stay up until replaced; without this a finished trip would
  /// leave the last instruction on the lens.
  static const Duration _staleAfter = Duration(seconds: 30);

  String? _lastInstruction;
  DateTime? _lastSent;
  Timer? _expiry;

  /// True while directions are on the lens, so other things that want the
  /// display can stand aside.
  bool get isNavigating => _lastInstruction != null;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) await _clear();
  }

  /// True when this notification is a navigation instruction rather than
  /// something the ordinary notification path should handle.
  bool isNavigation(ServiceNotificationEvent notification) {
    final package = notification.packageName ?? '';
    if (!supportedApps.containsKey(package)) return false;
    // A Maps notification that is not ongoing is a search result or a
    // reminder, not a manoeuvre.
    return notification.onGoing == true;
  }

  /// Handles a navigation notification. Returns true when it consumed it, so
  /// the caller does not also send it down the normal notification path.
  Future<bool> handle(ServiceNotificationEvent notification) async {
    // Raw material for the debug screen's capture, recorded for every
    // notification from a navigation app — including the ones isNavigation
    // rejects, because "it does not detect the instructions" is exactly a
    // claim about what gets rejected.
    final package = notification.packageName ?? '';
    if (supportedApps.containsKey(package)) {
      NavigationCapture.singleton.record(
        notification,
        ongoing: notification.onGoing == true,
      );
    }

    if (!isNavigation(notification)) return false;
    if (!await isEnabled()) return true;

    if (notification.hasRemoved == true) {
      await _clear();
      return true;
    }

    final instruction = format(notification.title, notification.content);
    if (instruction == null) return true;

    await _push(instruction);
    return true;
  }

  /// Builds the line shown on the lens from the notification's two fields.
  ///
  /// Maps puts the manoeuvre and distance in the title and the road in the
  /// text, but which is which varies by version and locale, so both are used
  /// and neither is assumed to be present.
  @visibleForTesting
  static String? format(String? title, String? content) {
    final manoeuvre = title?.trim() ?? '';
    final road = content?.trim() ?? '';

    if (manoeuvre.isEmpty && road.isEmpty) return null;
    if (road.isEmpty) return manoeuvre;
    if (manoeuvre.isEmpty) return road;

    // Maps sometimes repeats the road in both fields.
    if (road.toLowerCase().contains(manoeuvre.toLowerCase())) return road;
    if (manoeuvre.toLowerCase().contains(road.toLowerCase())) return manoeuvre;

    return '$manoeuvre\n$road';
  }

  Future<void> _push(String instruction) async {
    if (instruction == _lastInstruction) {
      _restartExpiry();
      return;
    }

    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minimumInterval) {
      return;
    }

    _lastInstruction = instruction;
    _lastSent = now;
    _restartExpiry();

    final speed = SpeedometerService.singleton.label;
    final line = speed == null ? instruction : '$instruction  ·  $speed';

    try {
      // Directions bypass the display preference: someone who turned the
      // display off is not navigating with it.
      await BluetoothManager.singleton.sendPriorityText(line);
    } catch (e) {
      debugPrint('NavigationService: could not display directions: $e');
    }
  }

  void _restartExpiry() {
    _expiry?.cancel();
    _expiry = Timer(_staleAfter, _clear);
  }

  Future<void> _clear() async {
    _expiry?.cancel();
    _expiry = null;
    if (_lastInstruction == null) return;

    _lastInstruction = null;
    _lastSent = null;

    try {
      await BluetoothManager.singleton.clearGlassesDisplay();
    } catch (e) {
      debugPrint('NavigationService: could not clear the display: $e');
    }
  }
}
