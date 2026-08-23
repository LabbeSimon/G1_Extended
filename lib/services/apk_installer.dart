import 'package:flutter/services.dart';

/// Hands a downloaded APK to Android's installer.
///
/// Android never lets an app install silently — the system's own sheet
/// confirms every install, and that is a guarantee, not an obstacle. What
/// this spares is everything before that sheet: the browser, the Downloads
/// folder, the hunt for the right file.
class ApkInstaller {
  const ApkInstaller._();

  static const MethodChannel _channel =
      MethodChannel('fr.simonlabbe.g1extended/apk_install');

  /// Whether the user has allowed this app to offer installs at all.
  ///
  /// A per-app switch Android 8 added, off by default, grantable only from
  /// a settings page — there is no dialog for it.
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens that settings page, on this app's own entry.
  static Future<void> openInstallPermission() =>
      _channel.invokeMethod('openInstallPermission');

  /// Shows the system install sheet for [path].
  static Future<void> install(String path) =>
      _channel.invokeMethod('install', {'path': path});
}
