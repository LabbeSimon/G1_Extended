import 'package:g1_extended/models/g1/text.dart';

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
    // Plain text by default (0x70), new content (0x01). It was 0x31 —
    // "Even AI displaying" — described as an example value and used as a
    // default everywhere, which is how ordinary text came to open the
    // assistant's screen.
    this.screenStatus = AIStatus.TEXT_SHOW | ScreenAction.NEW_CONTENT,
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
