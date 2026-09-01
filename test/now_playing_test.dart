import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/now_playing_service.dart';

/// A player's notification is not an alert. These pin the two things that
/// distinguish the two: what a track line looks like, and the fact that a
/// position update says nothing new.
void main() {
  group('Building the line', () {
    test('puts the track over the artist', () {
      expect(NowPlayingService.format('Redbone', 'Childish Gambino'),
          'Redbone\nChildish Gambino');
    });

    test('drops the album a player appends after the artist', () {
      // Spotify writes "Artist • Album"; the album is more than a lens needs.
      expect(NowPlayingService.format('Redbone', 'Childish Gambino • Awaken'),
          'Redbone\nChildish Gambino');
    });

    test('keeps whichever field is there when the other is empty', () {
      expect(NowPlayingService.format('Redbone', ''), 'Redbone');
      expect(NowPlayingService.format('', 'Childish Gambino'),
          'Childish Gambino');
      expect(NowPlayingService.format('  ', null), isNull);
    });

    test('does not repeat a field that says the same thing twice', () {
      expect(NowPlayingService.format('Bonobo', 'bonobo'), 'Bonobo');
    });

    test('survives a player that fills neither field', () {
      expect(NowPlayingService.format(null, null), isNull);
    });

    test('handles a podcast episode, which has no artist at all', () {
      expect(NowPlayingService.format('Episode 412 — The Deep Sea', null),
          'Episode 412 — The Deep Sea');
    });
  });

  group('Knowing which apps to read', () {
    test('the players people actually use are covered', () {
      expect(NowPlayingService.supportedApps, contains('com.spotify.music'));
      expect(NowPlayingService.supportedApps,
          contains('com.google.android.apps.youtube.music'));
      expect(NowPlayingService.supportedApps, contains('deezer.android.app'));
    });

    test('an ordinary app is not treated as a player', () {
      // Being wrong in this direction would swallow a real alert.
      expect(NowPlayingService.supportedApps,
          isNot(contains('com.whatsapp')));
      expect(NowPlayingService.supportedApps,
          isNot(contains('com.google.android.apps.maps')));
    });
  });
}
