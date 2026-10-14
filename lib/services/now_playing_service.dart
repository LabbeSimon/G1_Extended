import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/bluetooth_manager.dart';
import 'package:g1_extended/services/navigation_service.dart';

/// What is playing, on the lens, when it changes — and only then.
///
/// A player's notification is not an alert, and treating it as one is why
/// music was unpleasant on the glasses before this existed: Spotify rewrites
/// its ongoing notification continuously as the position advances, and every
/// one of those rewrites reached the ordinary notification path, so a single
/// song could flash the lens repeatedly while saying nothing new.
///
/// The rule here is the one navigation already follows: the wearer is told
/// when the *content* changes, never when the same content is merely
/// restated. Title and artist together are the identity of a track; a
/// position that moved is not a new track.
class NowPlayingService {
  NowPlayingService._internal();
  static final NowPlayingService singleton = NowPlayingService._internal();
  factory NowPlayingService() => singleton;

  /// Players whose ongoing notification describes a track.
  ///
  /// A list rather than a heuristic, deliberately: "has a media session" is
  /// not visible from a notification, and guessing from the shape of the
  /// text would swallow ordinary alerts from apps that happen to look
  /// similar. Anything absent here keeps its normal behaviour, which is the
  /// safe direction to be wrong in.
  static const Map<String, String> supportedApps = {
    'com.spotify.music': 'Spotify',
    'com.google.android.apps.youtube.music': 'YouTube Music',
    'com.google.android.youtube': 'YouTube',
    'deezer.android.app': 'Deezer',
    'com.apple.android.music': 'Apple Music',
    'com.soundcloud.android': 'SoundCloud',
    'tv.plex.labs.plexamp': 'Plexamp',
    'com.maxmpz.audioplayer': 'Poweramp',
    'org.videolan.vlc': 'VLC',
    'com.bambuna.podcastaddict': 'Podcast Addict',
    'au.com.shiftyjelly.pocketcasts': 'Pocket Casts',
    'com.ghostbusters.antennapod': 'AntennaPod',
    'de.danoeh.antennapod': 'AntennaPod',
    'code.name.monkey.retromusic': 'Retro Music',
    'com.aimp.player': 'AIMP',
  };

  static const String _enabledKey = 'now_playing_enabled';

  /// Even a genuine track change is not worth interrupting the lens for more
  /// often than this — skipping through a playlist would otherwise redraw
  /// once per skip, faster than anything can be read.
  static const Duration _minimumInterval = Duration(seconds: 3);

  /// A track announcement is news, not a status board: it says its piece and
  /// gets out of the way rather than sitting on the lens for the length of
  /// the song.
  static const Duration _showFor = Duration(seconds: 6);

  String? _lastTrack;
  DateTime? _lastSent;
  Timer? _expiry;

  /// True while a track is on the lens.
  bool get isShowing => _lastTrack != null;

  /// What is playing, or null when nothing is.
  String? get current => _lastTrack;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) await _clear();
  }

  /// True when this notification describes a track rather than an alert.
  bool isNowPlaying(ServiceNotificationEvent notification) {
    final package = notification.packageName ?? '';
    if (!supportedApps.containsKey(package)) return false;
    // A Spotify notification that is not ongoing is a recommendation or a
    // "your playlist is ready", not a transport control.
    return notification.onGoing == true;
  }

  /// Handles a player notification. Returns true when it consumed it, so the
  /// caller does not also send it down the ordinary notification path.
  Future<bool> handle(ServiceNotificationEvent notification) async {
    if (!isNowPlaying(notification)) return false;

    // Consumed either way once it is recognised as a player: an ordinary
    // banner for every position update is precisely what this exists to
    // prevent, and that must hold whether or not the feature is switched on.
    if (!await isEnabled()) return true;

    if (notification.hasRemoved == true) {
      await _clear();
      return true;
    }

    // Directions win the lens. Someone following a route through a junction
    // does not need the next song announced over the turn they are taking.
    if (NavigationService.singleton.isNavigating) return true;

    final track = format(notification.title, notification.content);
    if (track == null) return true;

    await _push(track);
    return true;
  }

  /// Builds the two lines shown on the lens.
  ///
  /// Players put the track in the title and the artist in the text, but not
  /// all of them, and some append the album after a separator. Both fields
  /// are used and neither is assumed to be there.
  @visibleForTesting
  static String? format(String? title, String? content) {
    final track = title?.trim() ?? '';
    final artist = content?.trim() ?? '';

    if (track.isEmpty && artist.isEmpty) return null;
    if (artist.isEmpty) return track;
    if (track.isEmpty) return artist;

    // "Artist • Album" is more than a lens needs; the artist alone is the
    // half that identifies the track to a listener.
    final justArtist = artist.split(RegExp(r'\s[•·—|]\s')).first.trim();
    final shown = justArtist.isEmpty ? artist : justArtist;

    if (shown.toLowerCase() == track.toLowerCase()) return track;

    return '$track\n$shown';
  }

  Future<void> _push(String track) async {
    // The rewrite storm lands here: same track, nothing to say.
    if (track == _lastTrack) return;

    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minimumInterval) {
      // Skipping quickly through a playlist. The track is still recorded so
      // the one that is actually settled on gets announced by the next
      // notification rather than being suppressed as a duplicate.
      _lastTrack = track;
      return;
    }

    _lastTrack = track;
    _lastSent = now;

    try {
      await BluetoothManager.singleton.sendPriorityText(track);
    } catch (e) {
      debugPrint('NowPlayingService: could not display the track: $e');
      return;
    }

    _restartExpiry();
  }

  void _restartExpiry() {
    _expiry?.cancel();
    _expiry = Timer(_showFor, () {
      // Only the display is transient. What is playing stays known, so the
      // next notification for the same track is still recognised as a
      // repeat rather than announced a second time.
      _expiry = null;
    });
  }

  Future<void> _clear() async {
    _expiry?.cancel();
    _expiry = null;
    _lastTrack = null;
    _lastSent = null;
  }

  /// Forgets what is playing. For tests and for switching the feature off.
  @visibleForTesting
  Future<void> reset() => _clear();
}
