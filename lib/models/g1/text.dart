import 'dart:convert';

import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/even_ai.dart';
import 'package:flutter/foundation.dart';

/// The status byte of a text packet, which is two fields in one.
///
/// The high nibble tells the glasses *what kind of thing* is on screen and
/// the low nibble what to do with it. This app had the high nibble wrong
/// everywhere: every piece of text — a teleprompter line, a speed reading,
/// a dictation echo — went out announcing itself as Even AI output, so the
/// glasses did the reasonable thing and opened the Even AI screen. Two
/// different constants in this codebase, 0x20 | 0x10 here and 0x31 in
/// even_ai.dart, both said the same thing: Even AI is displaying.
class AIStatus {
  /// Even AI is producing this, more to come.
  static const int DISPLAYING = 0x30;

  /// Even AI has finished producing this.
  static const int DISPLAY_COMPLETE = 0x40;

  /// Plain text, nothing to do with the assistant. What almost everything
  /// this app sends actually is.
  static const int TEXT_SHOW = 0x70;
}

class ScreenAction {
  /// Replace what is on screen with what follows.
  static const int NEW_CONTENT = 0x01;
}

class TextMessage {
  final String text;

  TextMessage(this.text);

  List<int> _sendTextPacket({
    required String textMessage,
    int pageNumber = 1,
    int maxPages = 1,
    int screenStatus = ScreenAction.NEW_CONTENT | AIStatus.TEXT_SHOW,
    int seq = 0,
  }) {
    List<int> textBytes = utf8.encode(textMessage);

    SendResultPacket result = SendResultPacket(
      command: Commands.SEND_RESULT,
      seq: seq,
      totalPackages: 1,
      currentPackage: 0,
      screenStatus: screenStatus,
      newCharPos0: 0,
      newCharPos1: 0,
      pageNumber: pageNumber,
      maxPages: maxPages,
      data: textBytes,
    );

    return result.build();
  }

  List<String> _formatTextLines(String textMessage) {
    // Assuming a maximum line length of 20 characters
    const int maxLineLength = 20;
    List<String> words = textMessage.split(' ');
    List<String> lines = [];
    String currentLine = '';

    for (String word in words) {
      if ((currentLine + word).length <= maxLineLength) {
        currentLine += (currentLine.isEmpty ? '' : ' ') + word;
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    return lines;
  }

  /// The same packets, under a caller-chosen status byte. For the debug
  /// sweep that establishes which value the firmware treats as plain text.
  List<List<int>> constructSendTextWithStatus(int screenStatus) {
    final chunks = <List<int>>[];
    final bytes = utf8.encode(text);
    chunks.add(_sendTextPacket(
      textMessage: text,
      screenStatus: screenStatus,
    ));
    debugPrint('constructSendTextWithStatus: ${bytes.length} byte(s) at '
        '0x${screenStatus.toRadixString(16)}');
    return chunks;
  }

  List<List<int>> constructSendText() {
    List<String> lines = _formatTextLines(text);
    int totalPages = ((lines.length + 4) / 5).ceil(); // 5 lines per page

    List<List<int>> packets = [];

    if (totalPages > 1) {
      debugPrint("Composeing $totalPages pages");
      int screenStatus = AIStatus.TEXT_SHOW | ScreenAction.NEW_CONTENT;

      packets.add(_sendTextPacket(
        textMessage: lines[0],
        pageNumber: 1,
        maxPages: totalPages,
        screenStatus: screenStatus,
      ));
    }

    String lastPageText = '';

    for (int pn = 1, page = 0; page < lines.length; pn++, page += 5) {
      List<String> pageLines = lines.sublist(
        page,
        (page + 5) > lines.length ? lines.length : (page + 5),
      );

      // Add vertical centering for pages with fewer than 5 lines
      if (pageLines.length < 5) {
        int padding = ((5 - pageLines.length) / 2).floor();
        pageLines = List.filled(padding, '') +
            pageLines +
            List.filled(5 - pageLines.length - padding, '');
      }

      String text = pageLines.join('\n');
      lastPageText = text;
      int screenStatus = AIStatus.TEXT_SHOW | ScreenAction.NEW_CONTENT;

      packets.add(_sendTextPacket(
        textMessage: text,
        pageNumber: pn,
        maxPages: totalPages,
        screenStatus: screenStatus,
      ));
    }

    // After all pages, send the last page again with DISPLAY_COMPLETE status
    int screenStatus = AIStatus.TEXT_SHOW | ScreenAction.NEW_CONTENT;

    packets.add(_sendTextPacket(
      textMessage: lastPageText,
      pageNumber: totalPages,
      maxPages: totalPages,
      screenStatus: screenStatus,
    ));

    return packets;
  }

  /// Build a single packet showing only the last page of text with DISPLAYING status.
  /// Used during streaming to avoid re-sending all pages on every update.
  List<int> constructStreamingText() {
    List<String> lines = _formatTextLines(text);
    int totalPages = ((lines.length + 4) / 5).ceil();

    // Get the last page's lines
    int lastPageStart = (totalPages - 1) * 5;
    List<String> pageLines = lines.sublist(
      lastPageStart,
      lastPageStart + 5 > lines.length ? lines.length : lastPageStart + 5,
    );

    // Vertical centering
    if (pageLines.length < 5) {
      int padding = ((5 - pageLines.length) / 2).floor();
      pageLines = List.filled(padding, '') +
          pageLines +
          List.filled(5 - pageLines.length - padding, '');
    }

    String pageText = pageLines.join('\n');
    int screenStatus = AIStatus.TEXT_SHOW | ScreenAction.NEW_CONTENT;

    return _sendTextPacket(
      textMessage: pageText,
      pageNumber: totalPages,
      maxPages: totalPages,
      screenStatus: screenStatus,
    );
  }
}
