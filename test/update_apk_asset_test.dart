import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/update_service.dart';

/// Picking the APK out of a release's assets. By suffix, never by exact
/// name: the asset is named after the tag, and an exact match would break
/// the update button the day the naming changes — silently, for everyone.
void main() {
  abiTests();
  Map<String, dynamic> release(List<Map<String, Object>> assets) =>
      {'tag_name': 'v9.9.9', 'assets': assets};

  test('finds the apk among other assets', () {
    final picked = UpdateService.pickApkAsset(release([
      {'name': 'checksums.txt', 'browser_download_url': 'u1', 'size': 100},
      {
        'name': 'g1-extended-v9.9.9.apk',
        'browser_download_url': 'https://x/apk',
        'size': 123456
      },
    ]));

    expect(picked?.$1, 'https://x/apk');
    expect(picked?.$2, 123456);
  });

  test('the name may change entirely, only the suffix matters', () {
    final picked = UpdateService.pickApkAsset(release([
      {'name': 'Whatever-Name.APK', 'browser_download_url': 'u', 'size': 1},
    ]));
    expect(picked, isNotNull);
  });

  test('no apk means no download offer, not a crash', () {
    expect(UpdateService.pickApkAsset(release([])), isNull);
    expect(UpdateService.pickApkAsset({'tag_name': 'v1'}), isNull);
    expect(
      UpdateService.pickApkAsset({
        'assets': [
          {'name': 'notes.pdf', 'browser_download_url': 'u', 'size': 5},
        ]
      }),
      isNull,
    );
  });

  test('a malformed asset is skipped rather than thrown on', () {
    final picked = UpdateService.pickApkAsset(release([
      {'name': 'g1.apk'}, // no url
    ]));
    expect(picked, isNull);
  });

  test('a missing size reads as zero, which the progress bar handles', () {
    final picked = UpdateService.pickApkAsset(release([
      {'name': 'g1.apk', 'browser_download_url': 'u'},
    ]));
    expect(picked?.$2, 0);
  });
}

/// Picking the build that matches the phone.
///
/// A release carries one APK per processor architecture. The universal
/// build is nearly twice the size, and the excess is native code for
/// processors the phone does not have — so the wrong choice doubles every
/// update, and on a beta channel that is the difference between updating
/// readily and putting it off.
void abiTests() {
  Map<String, Object> asset(String name, int size) => {
        'name': name,
        'browser_download_url': 'https://x/$name',
        'size': size,
      };

  Map<String, dynamic> split() => {
        'assets': [
          asset('g1-extended-v1.2.1-armeabi-v7a.apk', 44000000),
          asset('g1-extended-v1.2.1-arm64-v8a.apk', 46000000),
        ],
      };

  group('Matching the architecture', () {
    test('a 64-bit phone gets the 64-bit build', () {
      final picked = UpdateService.pickApkAsset(
        split(),
        abis: ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(picked!.$1, contains('arm64-v8a'));
    });

    test('an older 32-bit phone gets the 32-bit build', () {
      final picked = UpdateService.pickApkAsset(
        split(),
        abis: ['armeabi-v7a'],
      );
      expect(picked!.$1, contains('armeabi-v7a'));
    });

    test('preference order is honoured, not asset order', () {
      // Android lists the best architecture first, and so must this.
      final picked = UpdateService.pickApkAsset(
        split(),
        abis: ['armeabi-v7a', 'arm64-v8a'],
      );
      expect(picked!.$1, contains('armeabi-v7a'));
    });
  });

  group('When nothing matches', () {
    test('an unrecognised architecture takes the universal build', () {
      final picked = UpdateService.pickApkAsset(
        {
          'assets': [
            asset('g1-extended-v1.2.1-arm64-v8a.apk', 46000000),
            asset('g1-extended-v1.2.1.apk', 88000000),
          ]
        },
        abis: ['riscv64'],
      );
      expect(picked!.$1, endsWith('g1-extended-v1.2.1.apk'),
          reason: 'the universal build is the honest fallback');
    });

    test('a wrong-architecture build is never offered', () {
      // It would install and then refuse to run, which is worse than
      // reporting no update at all.
      final picked = UpdateService.pickApkAsset(
        {
          'assets': [asset('g1-extended-v1.2.1-arm64-v8a.apk', 46000000)]
        },
        abis: ['armeabi-v7a'],
      );
      expect(picked, isNull);
    });

    test('a release with only a universal build still works', () {
      final picked = UpdateService.pickApkAsset(
        {
          'assets': [asset('g1-extended-v1.2.0.apk', 59000000)]
        },
        abis: ['arm64-v8a'],
      );
      expect(picked!.$1, contains('v1.2.0'));
    });
  });

  group('The beta channel checks far more often', () {
    test('half-hourly against twelve-hourly', () {
      // A build finishes and the phone that asked for betas should not
      // learn about it the following afternoon.
      expect(UpdateService.betaInterval.inMinutes, 30);
      expect(
        UpdateService.betaInterval.inMinutes,
        lessThan(UpdateService.minimumInterval.inMinutes),
      );
    });
  });
}
