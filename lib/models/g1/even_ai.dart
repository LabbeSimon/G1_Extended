import 'dart:typed_data';

class SendResultPacket {
  final int command;
  final int seq;
  final int totalPackages;
  final int currentPackage;
  final int screenStatus;
  final int newCharPos0;
  final int newCharPos1;
  final int pageNumber;
  final int maxPages;
  final List<int> data;

  SendResultPacket({
    required this.command,
    this.seq = 0,
    this.totalPackages = 1,
    this.currentPackage = 0,
    this.screenStatus = 0x31, // Example value
    this.newCharPos0 = 0,
    this.newCharPos1 = 0,
    this.pageNumber = 1,
    this.maxPages = 1,
    required this.data,
  });

  List<int> build() {
    return [
      command,
      seq & 0xFF,
      totalPackages & 0xFF,
      currentPackage & 0xFF,
      screenStatus & 0xFF,
      newCharPos0 & 0xFF,
      newCharPos1 & 0xFF,
      pageNumber & 0xFF,
      maxPages & 0xFF,
      ...data,
    ];
  }
}

/// The glasses' own Even AI screen, command 0x54. The firmware opens it by
/// itself when the left temple is held.
///
/// Frames as the official Even app 1.6.5 builds them; see
/// docs/protocol/even-ai-transcribe-translate.md, section 3.
abstract final class EvenAiProtocol {
  static const int command = 0x54;
  static const int _status = 0x01;

  /// Ends the AI session: status 0, which is how the official app closes the
  /// AI screen once the answer has been read (its `exitAI`). Clearing the
  /// text instead leaves the window up, scroll bar and all.
  static Uint8List exit({required int seq}) =>
      Uint8List.fromList([command, 0x06, 0x00, seq % 255, _status, 0x00]);

  /// The official app's check on the reply: same command, sub 0x01, 0xC9.
  static bool acceptsStatus(List<int> reply) =>
      reply.length > 5 &&
      reply[0] == command &&
      reply[4] == _status &&
      reply[5] == 0xC9;
}
