import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/permission_manager.dart';

/// definitionOf uses firstWhere with no fallback, so an enum value without a
/// definition does not degrade — it throws, from whatever screen happened to
/// ask. These check the table is complete and says what it means.
void main() {
  test('every permission group has a definition', () {
    for (final id in AppPermission.values) {
      expect(() => PermissionManager.definitionOf(id), returnsNormally,
          reason: '$id has no definition');
    }
  });

  test('no two groups share a title', () {
    // Two entries called "Notifications" is how the app came to ask for
    // permission to *post* notifications while never asking to *read* them:
    // the wrong one looked granted and nobody could tell them apart.
    final titles = AppPermission.values
        .map((id) => PermissionManager.definitionOf(id).title.toLowerCase())
        .toList();
    expect(titles.toSet().length, titles.length,
        reason: 'two permission groups are named the same thing');
  });

  test('the two notification groups are distinct and both present', () {
    final post = PermissionManager.definitionOf(AppPermission.notifications);
    final read =
        PermissionManager.definitionOf(AppPermission.notificationAccess);

    // Posting alerts is a runtime permission; reading other apps' alerts is
    // not one at all, and is delegated.
    expect(post.permissions, isNotEmpty);
    expect(read.permissions, isEmpty);
    expect(read.requiredForCoreFlow, isTrue,
        reason: 'the glasses do nothing without it');
    expect(read.androidOnly, isTrue);
  });

  test('groups with no runtime permission say so rather than looking granted',
      () {
    // An empty permission list reads as "granted" in PermissionSummary, so a
    // group with nothing behind it must be one the manager delegates.
    for (final id in AppPermission.values) {
      final definition = PermissionManager.definitionOf(id);
      if (definition.permissions.isNotEmpty) continue;
      expect(
        id == AppPermission.calendar || id == AppPermission.notificationAccess,
        isTrue,
        reason: '$id has no permissions and nothing handles it, so it will '
            'always report itself as granted',
      );
    }
  });

  test('every group has a description that explains itself', () {
    for (final id in AppPermission.values) {
      final definition = PermissionManager.definitionOf(id);
      expect(definition.title.trim(), isNotEmpty, reason: '$id has no title');
      expect(definition.description.trim().length, greaterThan(20),
          reason: '$id is not explained');
    }
  });
}
