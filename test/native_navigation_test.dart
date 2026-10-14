import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/models/g1/navigation.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';
import 'package:g1_extended/services/native_navigation.dart';

/// Echoes each frame back as the glasses do, unless told to refuse.
class _Link implements TeleprompterLink {
  bool refuseLeft = false;
  final List<(GlassSide, Uint8List)> sent = [];

  @override
  bool isConnected = true;

  @override
  Future<List<int>?> exchange(
    GlassSide side,
    Uint8List frame, {
    required bool Function(List<int> reply) accept,
    required Duration timeout,
  }) async {
    sent.add((side, frame));
    final status = refuseLeft && side == GlassSide.left ? 0xCA : 0xC9;
    return [0x0A, 0x06, 0x00, frame[3], frame[4], status];
  }

  List<(GlassSide, int)> get steps => [for (final s in sent) (s.$1, s.$2[4])];
}

const _route = NavigationRoute(icon: NavigationIcon.left, distance: '50 m', road: 'Rue X');

void main() {
  test('opens, shows, beats on the right, and closes', () async {
    final link = _Link();
    final nav = NativeNavigation(link: link);

    expect(await nav.show(_route), isTrue);
    expect(nav.isOpen, isTrue);
    expect(link.steps, [
      (GlassSide.left, NavigationProtocol.startSub),
      (GlassSide.right, NavigationProtocol.startSub),
      (GlassSide.left, NavigationProtocol.routeSub),
      (GlassSide.right, NavigationProtocol.routeSub),
    ]);

    await Future.delayed(const Duration(milliseconds: 1150));
    expect(link.steps.last, (GlassSide.right, NavigationProtocol.heartbeatSub));

    await nav.close();
    expect(nav.isOpen, isFalse);
    expect(link.steps.sublist(link.steps.length - 2), [
      (GlassSide.left, NavigationProtocol.exitSub),
      (GlassSide.right, NavigationProtocol.exitSub),
    ]);
  });

  test('refused on the left: never opened, so the caller falls back', () async {
    final link = _Link()..refuseLeft = true;
    final nav = NativeNavigation(link: link);

    expect(await nav.show(_route), isFalse);
    expect(nav.isOpen, isFalse);
    expect(link.steps, List.filled(4, (GlassSide.left, NavigationProtocol.startSub)));
    await nav.close();
    expect(link.steps, hasLength(4), reason: 'nothing to close');
  });

  test('no glasses, no frames', () async {
    final link = _Link()..isConnected = false;
    expect(await NativeNavigation(link: link).show(_route), isFalse);
    expect(link.sent, isEmpty);
  });
}
