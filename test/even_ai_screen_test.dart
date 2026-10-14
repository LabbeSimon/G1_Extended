import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/even_ai.dart';
import 'package:g1_extended/models/g1/glass.dart';
import 'package:g1_extended/services/even_ai_screen.dart';
import 'package:g1_extended/services/glasses_teleprompter.dart';

/// Answers each side from [reply]; records what was sent where.
class _Link implements TeleprompterLink {
  _Link(this.reply);
  final List<int>? Function(GlassSide side) reply;
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
    return reply(side);
  }
}

const _ok = [0x54, 0x07, 0x00, 0x00, 0x01, 0xC9, 0x00];
const _refused = [0x54, 0x07, 0x00, 0x00, 0x01, 0xCA, 0x00];

void main() {
  test('the official exitAI frame: status 0', () {
    expect(EvenAiProtocol.exit(seq: 3), [0x54, 0x06, 0x00, 0x03, 0x01, 0x00]);
    expect(EvenAiProtocol.exit(seq: 300)[3], 300 % 255);
  });

  test('left then right, once both take it', () async {
    final link = _Link((_) => _ok);
    expect(await EvenAiScreen(link: link).close(), isTrue);
    expect(link.sent.map((s) => s.$1), [GlassSide.left, GlassSide.right]);
  });

  test('a left refusal never reaches the right, three times over', () async {
    final link = _Link((side) => side == GlassSide.left ? _refused : _ok);
    expect(await EvenAiScreen(link: link).close(), isFalse);
    expect(link.sent.map((s) => s.$1), List.filled(3, GlassSide.left));
  });

  test('nothing is sent with the glasses away', () async {
    final link = _Link((_) => _ok)..isConnected = false;
    expect(await EvenAiScreen(link: link).close(), isFalse);
    expect(link.sent, isEmpty);
  });
}
