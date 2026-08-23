import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/update_service.dart';

/// Version ordering, including pre-releases.
///
/// The suffix used to be discarded, which made 1.1.2-beta.6 and 1.1.2
/// equal — so the beta channel would have compared every pre-release
/// against the running build, found no difference, and offered nothing at
/// all. Silently, forever. These pin semantic versioning's actual rules.
void main() {
  group('Plain releases', () {
    test('numeric, not alphabetical — 1.0.10 follows 1.0.9', () {
      expect(UpdateService.isNewer('1.0.10', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('1.0.9', '1.0.10'), isFalse);
    });

    test('the same version is not an update', () {
      expect(UpdateService.isNewer('1.1.2', '1.1.2'), isFalse);
    });

    test('build metadata after + is not a version', () {
      expect(UpdateService.isNewer('1.1.2+9', '1.1.2+3'), isFalse);
    });

    test('a leading v is decoration', () {
      expect(UpdateService.isNewer('v1.2.0', '1.1.9'), isTrue);
    });
  });

  group('Pre-releases sort before the release they lead to', () {
    test('the release beats its own beta', () {
      expect(UpdateService.isNewer('1.1.2', '1.1.2-beta.6'), isTrue);
    });

    test('and a beta does not beat the release', () {
      expect(UpdateService.isNewer('1.1.2-beta.6', '1.1.2'), isFalse);
    });

    test('a beta of a later version still wins', () {
      expect(UpdateService.isNewer('1.2.0-beta.1', '1.1.2'), isTrue);
    });
  });

  group('Betas among themselves', () {
    test('later beta wins — this is what the channel lives on', () {
      expect(UpdateService.isNewer('1.1.2-beta.6', '1.1.2-beta.5'), isTrue);
      expect(UpdateService.isNewer('1.1.2-beta.5', '1.1.2-beta.6'), isFalse);
    });

    test('numerically, so beta.10 follows beta.9', () {
      expect(UpdateService.isNewer('1.1.2-beta.10', '1.1.2-beta.9'), isTrue);
    });

    test('identical betas are not an update', () {
      expect(UpdateService.isNewer('1.1.2-beta.5', '1.1.2-beta.5'), isFalse);
    });

    test('more parts beat fewer when the shared ones match', () {
      expect(UpdateService.isNewer('1.1.2-beta.1', '1.1.2-beta'), isTrue);
    });
  });

  group('Picking from a release listing', () {
    Map<String, Object> release(String tag, {bool draft = false}) =>
        {'tag_name': tag, 'draft': draft};

    test('the newest by version, not by position in the list', () {
      // GitHub orders by creation date, which is not ordering by version:
      // a patch cut after a later beta would sort ahead of it.
      final picked = UpdateService.pickNewestRelease([
        release('v1.1.1'),
        release('v1.1.2-beta.7'),
        release('v1.1.2-beta.3'),
      ]);
      expect(picked!['tag_name'], 'v1.1.2-beta.7');
    });

    test('a stable release outranks the betas leading to it', () {
      final picked = UpdateService.pickNewestRelease([
        release('v1.1.2-beta.7'),
        release('v1.1.2'),
      ]);
      expect(picked!['tag_name'], 'v1.1.2');
    });

    test('drafts are nobody\'s update', () {
      final picked = UpdateService.pickNewestRelease([
        release('v2.0.0', draft: true),
        release('v1.1.2'),
      ]);
      expect(picked!['tag_name'], 'v1.1.2');
    });

    test('an empty or malformed listing yields nothing, not a crash', () {
      expect(UpdateService.pickNewestRelease([]), isNull);
      expect(UpdateService.pickNewestRelease(['nonsense', 42]), isNull);
      expect(UpdateService.pickNewestRelease([{'no': 'tag'}]), isNull);
    });
  });
}
