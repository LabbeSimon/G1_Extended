import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/update_service.dart';

void main() {
  group('Release tag normalisation', () {
    test('strips a leading v', () {
      expect(UpdateService.normalise('v1.2.3'), '1.2.3');
      expect(UpdateService.normalise('V1.2.3'), '1.2.3');
    });

    test('leaves a bare version alone', () {
      expect(UpdateService.normalise('1.2.3'), '1.2.3');
    });
  });

  group('Version comparison', () {
    test('detects a newer patch, minor and major', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('rejects the same version', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('rejects an older version', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
      expect(UpdateService.isNewer('1.9.9', '2.0.0'), isFalse);
    });

    test('compares numerically, not as text', () {
      // The bug a string comparison would introduce: "1.0.10" < "1.0.9".
      expect(UpdateService.isNewer('1.0.10', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('1.0.9', '1.0.10'), isFalse);
      expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
    });

    test('treats missing segments as zero', () {
      expect(UpdateService.isNewer('1.1', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('2', '1.9.9'), isTrue);
    });

    test('handles the v prefix on either side', () {
      expect(UpdateService.isNewer('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('v1.0.0', 'v1.0.0'), isFalse);
    });

    test('ignores a build suffix', () {
      expect(UpdateService.isNewer('1.0.0+5', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.1+1', '1.0.0+9'), isTrue);
    });

    test('never offers an update for an unparseable tag', () {
      expect(UpdateService.isNewer('nightly', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('', '1.0.0'), isFalse);
    });
  });
}
