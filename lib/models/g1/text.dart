import 'dart:convert';

import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/even_ai.dart';
import 'package:flutter/foundation.dart';

// Define AIStatus and ScreenAction constants
class AIStatus {
  static const int DISPLAYING = 0x20;
  static const int DISPLAY_COMPLETE = 0x40;
}

class ScreenAction {
  static const int NEW_CONTENT = 0x10;
}

class TextMessage {
  final String text;

  /// How wide a line is allowed to be, in characters.
  ///
  /// Defaults to [charsPerLine]. Overridable because the number is disputed
  /// and the only arbiter is a pair of glasses: see the note on
  /// [charsPerLine], and the three buttons in Settings → Debug.
  final int charactersPerLine;

  TextMessage(this.text, {this.charactersPerLine = charsPerLine});

  /// The status byte this app has always sent: 0x30.
  static const int statusToday =
      AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

  /// The same mode, with the action where the community spec puts it.
  ///
  /// openg1-sdk and g1bridge both read the high nibble as the mode and the
  /// low one as the action, which makes "Even AI, new content" 0x31 rather
  /// than 0x30. Neither of them has been run against these glasses by
  /// anyone here, and the current byte does display, so this is a candidate
  /// to try on hardware rather than a fix to apply blind.
  static const int statusAiNewContent = 0x31;

  /// Plain text rather than an Even AI answer: 0x70 with the action bit.
  ///
  /// The one the SDK's own conformance vector uses for `send_text`.
  static const int statusTextShow = 0x71;

  List<int> _sendTextPacket({
    required String textMessage,
    int pageNumber = 1,
    int maxPages = 1,
    int screenStatus = ScreenAction.NEW_CONTENT | AIStatus.DISPLAYING,
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

  /// How many characters the lens fits on one line.
  ///
  /// Disputed, and worth reading before trusting: the teleprompter's own
  /// paginator says "measured on the hardware: about 25 characters across,
  /// 7 lines visible" (`lib/services/teleprompter_tracker.dart`), and its
  /// pages go out through this very command. Forty comes from two other
  /// implementations measuring the 488 pixel column at font size 21. Both
  /// cannot be right for the same command, so Settings → Debug sends the
  /// same paragraph at twenty, twenty-five and forty, and whichever fills
  /// the lens without spilling wins.
  ///
  /// Twenty, inherited from the fork this app comes from, is half the panel:
  /// the firmware composes its text in a 488 pixel column at font size 21,
  /// which is about forty characters. Two independent implementations
  /// measure the same forty (openg1-sdk's panel calibration and g1bridge,
  /// the latter tested on hardware), and the lens mirror in Settings →
  /// Debug shows the difference without wearing anything: at twenty, lines
  /// break mid-sentence and a message needs twice the pages it should.
  static const int charsPerLine = 40;

  /// One page, with the screen-status byte named rather than assumed.
  ///
  /// The Debug screen sends the same sentence three times with the three
  /// candidate bytes. Whichever behaves best on a face settles a question
  /// no amount of reading settles.
  List<int> constructPageWithStatus({required int screenStatus}) {
    final lines = _formatTextLines(text);
    final page = lines.take(5).join('\n');
    return _sendTextPacket(
      textMessage: page,
      pageNumber: 1,
      maxPages: 1,
      screenStatus: screenStatus,
    );
  }

  List<String> _formatTextLines(String textMessage) {
    final int maxLineLength = charactersPerLine;
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

  List<List<int>> constructSendText() {
    List<String> lines = _formatTextLines(text);
    int totalPages = ((lines.length + 4) / 5).ceil(); // 5 lines per page

    List<List<int>> packets = [];

    if (totalPages > 1) {
      debugPrint("Composeing $totalPages pages");
      int screenStatus = AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

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
      int screenStatus = AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

      packets.add(_sendTextPacket(
        textMessage: text,
        pageNumber: pn,
        maxPages: totalPages,
        screenStatus: screenStatus,
      ));
    }

    // After all pages, send the last page again with DISPLAY_COMPLETE status
    int screenStatus = AIStatus.DISPLAY_COMPLETE;

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
    int screenStatus = AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

    return _sendTextPacket(
      textMessage: pageText,
      pageNumber: totalPages,
      maxPages: totalPages,
      screenStatus: screenStatus,
    );
  }
}
