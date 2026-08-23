import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/update_service.dart';

/// Picking the APK out of a release's assets. By suffix, never by exact
/// name: the asset is named after the tag, and an exact match would break
/// the update button the day the naming changes — silently, for everyone.
void main() {
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
