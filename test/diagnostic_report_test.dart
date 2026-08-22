import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/diagnostic_report.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The redaction switch decides whether anything tying the report to a person
/// or a specific pair of glasses is written at all. It defaults to on, so
/// these pin that default down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reading BluetoothManager.singleton starts the notification listener from
  // its constructor, so merely building a report reaches for a platform
  // channel. Stubbing it keeps this test about redaction; the side effect in
  // that constructor is worth removing on its own merits.
  void stubPlatformChannels() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      MethodChannel('x-slayer/notifications_channel'),
      MethodChannel('flutter_blue_plus/methods'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
    }
  }

  setUp(() {
    stubPlatformChannels();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'G1 Extended',
      packageName: 'fr.simonlabbe.g1extended',
      version: '1.0.0',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  test('redaction is on when the user has never chosen', () async {
    expect(await DiagnosticReport.singleton.isRedacted(), isTrue);
  });

  test('the choice survives a read back', () async {
    await DiagnosticReport.singleton.setRedacted(false);
    expect(await DiagnosticReport.singleton.isRedacted(), isFalse);

    await DiagnosticReport.singleton.setRedacted(true);
    expect(await DiagnosticReport.singleton.isRedacted(), isTrue);
  });

  test('a redacted report omits the identifying fields entirely', () async {
    await DiagnosticReport.singleton.setRedacted(true);
    final report = await DiagnosticReport.singleton.build();

    expect((report['report'] as Map)['redacted'], isTrue);

    // Absent, not blank: an empty string still says a field exists.
    expect((report['app'] as Map).containsKey('package'), isFalse);
    expect((report['platform'] as Map).containsKey('osVersion'), isFalse);
  });

  test('the version is kept, being what a bug report needs', () async {
    final report = await DiagnosticReport.singleton.build();
    expect((report['app'] as Map).containsKey('version'), isTrue);
    expect((report['platform'] as Map).containsKey('os'), isTrue);
  });

  test('opting in restores the identifying fields', () async {
    await DiagnosticReport.singleton.setRedacted(false);
    final report = await DiagnosticReport.singleton.build();

    expect((report['report'] as Map)['redacted'], isFalse);
    expect((report['app'] as Map).containsKey('package'), isTrue);
    expect((report['platform'] as Map).containsKey('osVersion'), isTrue);
  });
}
