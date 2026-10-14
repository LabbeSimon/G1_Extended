import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/home_assistant_service.dart';
import 'package:g1_extended/services/open_meteo_weather_service.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/services/voice_commands.dart';

/// Carries out a recognised command and says what happened.
///
/// Almost everything here is something the phone can do itself. Sending it
/// to a
/// language model instead would be slower, would fail without a network, and
/// in the case of replying to a message is not something a model can do at
/// all — the reply action belongs to the notification, and only the app
/// holding it can use it.
class VoiceCommandRunner {
  VoiceCommandRunner._internal();
  static final VoiceCommandRunner singleton = VoiceCommandRunner._internal();
  factory VoiceCommandRunner() => singleton;

  /// The last notification that offered a reply action.
  ///
  /// Android hands the action out with the notification and it expires with
  /// it, so this is a live handle rather than an identifier: replying half an
  /// hour later will simply fail, which is the correct behaviour.
  ServiceNotificationEvent? _replyable;

  static const Duration _replyWindow = Duration(minutes: 10);
  DateTime? _replyableAt;

  /// Remembers a notification that can be answered.
  void remember(ServiceNotificationEvent notification) {
    if (notification.canReply != true) return;
    if (notification.hasRemoved == true) return;

    _replyable = notification;
    _replyableAt = DateTime.now();
  }

  bool get hasReplyable {
    if (_replyable == null || _replyableAt == null) return false;
    return DateTime.now().difference(_replyableAt!) < _replyWindow;
  }

  /// Runs [match] and returns the line to show on the glasses.
  Future<String> run(VoiceCommandMatch match) async {
    return switch (match.kind) {
      VoiceCommandKind.reply => await _reply(match.argument),
      VoiceCommandKind.weather => await _weather(),
      VoiceCommandKind.note => await _note(match.argument),
      VoiceCommandKind.clear => await _clear(),
      VoiceCommandKind.call => await _call(match.argument),
      VoiceCommandKind.house => await _house(match.argument),
    };
  }

  /// Hands a whole sentence to Home Assistant's own conversation agent.
  ///
  /// The one command here that leaves the phone, and it does so because
  /// there is no other way: only the house knows what lights it has. What
  /// it does *not* do is interpret the sentence — Home Assistant already
  /// has intent matching, in the wearer's own language, over their own
  /// entities, and a second guess made here could only be worse.
  Future<String> _house(String sentence) async {
    final result = await HomeAssistantService.singleton.converse(sentence);
    return switch (result) {
      HaOk(:final text) => text,
      HaFailure(:final reason) => reason,
    };
  }

  Future<String> _reply(String message) async {
    final target = _replyable;
    if (target == null || !hasReplyable) {
      return 'Nothing recent to reply to';
    }

    try {
      final sent = await target.sendReply(message);
      if (!sent) return 'The app refused the reply';

      _replyable = null;
      _replyableAt = null;
      return 'Replied: $message';
    } catch (e) {
      debugPrint('VoiceCommandRunner: reply failed: $e');
      return 'Could not reply';
    }
  }

  Future<String> _weather() async {
    final days = await OpenMeteoWeatherService().getWeekForecast();
    if (days == null || days.isEmpty) return 'No forecast available';

    return formatForecast(days);
  }

  /// Squeezes a week onto a lens: one short line per day, and only as many
  /// days as will fit.
  @visibleForTesting
  static String formatForecast(
    List<DailyForecast> days, {
    int maxDays = 5,
  }) {
    final format = DateFormat('EEE');
    return days
        .take(maxDays)
        .map((day) =>
            '${format.format(day.date)} ${day.low.round()}/${day.high.round()}°')
        .join('   ');
  }

  Future<String> _note(String text) async {
    // The last slot is the one a spoken note goes to, so it never overwrites
    // something typed deliberately into slot one.
    // Used to overwrite slot four every time, destroying whatever was there.
    // A dictated note now joins the library and takes a slot only if one is
    // going spare.
    await NotesLibrary.singleton.create(
      title: 'Note',
      body: text,
      pinIfPossible: true,
    );
    return 'Noted';
  }

  Future<String> _clear() async {
    await BluetoothManager.singleton.clearGlassesDisplay();
    return '';
  }

  Future<String> _call(String who) async {
    final number = phoneNumberIn(who);
    if (number == null) {
      // Resolving a name would need the contacts permission, which this app
      // deliberately does not ask for. Saying so is better than failing
      // silently and better than asking for contacts to place one call.
      return 'Say a number, or dial $who yourself';
    }

    final uri = Uri(scheme: 'tel', path: number);
    try {
      // ACTION_DIAL opens the dialer with the number filled in. It places no
      // call by itself, which is why it needs no permission.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Dialling $number';
    } catch (e) {
      debugPrint('VoiceCommandRunner: could not open the dialler: $e');
      return 'Could not open the dialler';
    }
  }

  /// Pulls a dialable number out of what was heard, or null if it is a name.
  @visibleForTesting
  static String? phoneNumberIn(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 6) return null;
    if (RegExp(r'[a-zA-Z]').allMatches(text).length > 2) return null;
    return digits;
  }
}
