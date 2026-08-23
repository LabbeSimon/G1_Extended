import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/extension_manifest.dart';

/// The limits ARE the security model, so each is pinned by a test that says
/// what it protects against.
void main() {
  Map<String, dynamic> good() => {
        'formatVersion': 1,
        'id': 'meteo-marine',
        'name': 'Météo marine',
        'author': 'Simon',
        'version': '1.0.0',
        'description': 'La houle sur le verre.',
        'cards': [
          {
            'title': 'Houle',
            'template': 'Houle {value} m',
            'sourceUrl': 'https://example.org/houle.json',
            'sourcePath': 'data.height',
            'refreshMinutes': 30,
          },
        ],
      };

  group('A well-formed manifest', () {
    test('parses whole', () {
      final manifest = ExtensionManifestParser.parse(good());
      expect(manifest.id, 'meteo-marine');
      expect(manifest.cards, hasLength(1));
      expect(manifest.cards.first.sourceUrl, 'https://example.org/houle.json');
    });

    test('lists every address it will contact', () {
      final manifest = ExtensionManifestParser.parse(good());
      expect(manifest.sourceUrls, ['https://example.org/houle.json']);
    });

    test('a card can be purely local, with no source at all', () {
      final json = good();
      json['cards'] = [
        {'title': 'Heure', 'template': '{time}'},
      ];
      final manifest = ExtensionManifestParser.parse(json);
      expect(manifest.cards.first.sourceUrl, isNull);
      expect(manifest.sourceUrls, isEmpty);
    });
  });

  group('What gets refused, and why it matters', () {
    test('http, because a stranger\'s card does not get a weaker rule '
        'than your own', () {
      final json = good();
      (json['cards'] as List)[0] = {
        'title': 'Houle',
        'template': '{value}',
        'sourceUrl': 'http://example.org/houle.json',
      };
      expect(() => ExtensionManifestParser.parse(json),
          throwsA(isA<ManifestRejected>()));
    });

    test('a future format version, because silently half-reading a newer '
        'format is worse than saying "update the app"', () {
      final json = good()..['formatVersion'] = 2;
      expect(() => ExtensionManifestParser.parse(json),
          throwsA(isA<ManifestRejected>()));
    });

    test('more cards than the lens has slots', () {
      final json = good();
      json['cards'] = List.generate(
          5, (i) => {'title': 'c$i', 'template': 't'});
      expect(() => ExtensionManifestParser.parse(json),
          throwsA(isA<ManifestRejected>()));
    });

    test('an id that could not be a directory or a key', () {
      for (final id in ['Ça va pas', 'UPPER', 'a b', '', '-lead']) {
        final json = good()..['id'] = id;
        expect(() => ExtensionManifestParser.parse(json),
            throwsA(isA<ManifestRejected>()),
            reason: '"$id" should have been refused');
      }
    });

    test('an empty cards list — an extension that does nothing is a '
        'mistake, not a minimalist statement', () {
      final json = good()..['cards'] = [];
      expect(() => ExtensionManifestParser.parse(json),
          throwsA(isA<ManifestRejected>()));
    });

    test('missing identity fields', () {
      for (final key in ['id', 'name', 'author', 'version']) {
        final json = good()..remove(key);
        expect(() => ExtensionManifestParser.parse(json),
            throwsA(isA<ManifestRejected>()),
            reason: '$key should be required');
      }
    });
  });

  group('Third parties poll gently', () {
    test('a refresh below the floor is raised, not honoured', () {
      final json = good();
      (json['cards'] as List)[0]['refreshMinutes'] = 1;
      final manifest = ExtensionManifestParser.parse(json);
      expect(manifest.cards.first.refreshMinutes,
          ExtensionManifestParser.minRefreshMinutes);
    });
  });
}
