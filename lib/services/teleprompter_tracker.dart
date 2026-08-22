import 'package:flutter/foundation.dart';

/// Follows a reader through a script by listening to what they say.
///
/// Speech recognition is wrong often enough that exact matching is useless: a
/// single misheard word would stall the script forever. So this looks for the
/// recognised words *ahead* of where the reader currently is, scores each
/// candidate position, and moves only when one is clearly better than the
/// noise.
///
/// Three rules keep it honest:
///
///  * it never goes backwards, because a recogniser repeating itself must not
///    drag the reader back up the page;
///  * it only searches a window ahead, because scripts repeat phrases and a
///    global search would jump to the wrong stanza;
///  * it needs several words to agree, because one common word matching by
///    chance is not evidence of anything.
class TeleprompterTracker {
  TeleprompterTracker(String script) : words = _tokenise(script);

  /// How far ahead to look for what was just said.
  static const int searchWindow = 40;

  /// Recognised words considered at a time.
  static const int phraseLength = 5;

  /// A candidate needs at least this many of them to match.
  static const int minimumMatches = 2;

  /// The script, reduced to comparable words.
  final List<String> words;

  int _position = 0;

  /// How far through the script the reader is, in words.
  int get position => _position;

  bool get isFinished => _position >= words.length;

  /// Progress from 0.0 to 1.0.
  double get progress => words.isEmpty ? 1 : _position / words.length;

  /// Feeds in what the recogniser heard. Returns the new position when it
  /// moved, or null when nothing convincing was found.
  int? feed(String transcript) {
    if (words.isEmpty) return null;

    final heard = _tokenise(transcript);
    if (heard.isEmpty) return null;

    // Only the tail matters: the recogniser resends the whole sentence as it
    // refines it, and the reader is at the end of it, not the start.
    final phrase = heard.length <= phraseLength
        ? heard
        : heard.sublist(heard.length - phraseLength);

    final best = _bestMatch(phrase);
    if (best == null) return null;

    _position = best;
    return _position;
  }

  /// Finds where in the window ahead the phrase sits, if anywhere.
  int? _bestMatch(List<String> phrase) {
    final end = (_position + searchWindow).clamp(0, words.length);

    var bestIndex = -1;
    var bestScore = 0;

    for (var start = _position; start < end; start++) {
      var score = 0;
      for (var i = 0; i < phrase.length && start + i < words.length; i++) {
        if (words[start + i] == phrase[i]) score++;
      }

      // Ties go to the earliest position: overshooting loses the reader's
      // place, lagging only means the next phrase catches up.
      if (score > bestScore) {
        bestScore = score;
        bestIndex = start;
      }
    }

    if (bestScore < minimumMatches || bestIndex < 0) return null;

    // The reader has said these words, so they are past them.
    return (bestIndex + bestScore).clamp(0, words.length);
  }

  /// Jumps to a position, for the manual controls.
  void seek(int position) {
    _position = position.clamp(0, words.length);
  }

  void reset() => _position = 0;

  /// Lowercases, strips punctuation and splits. Comparing raw text would fail
  /// on every comma the recogniser does not produce.
  static List<String> _tokenise(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\p{L}\p{N}\s']", unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  @override
  String toString() =>
      'TeleprompterTracker($_position/${words.length})';
}

/// Splits a script into what fits on the lens at once.
///
/// The G1 shows roughly seven lines of about twenty-five characters. Breaking
/// on words rather than characters is what stops a line ending mid-syllable.
@immutable
class ScriptPage {
  /// The text as shown.
  final String text;

  /// Index of the first word of this page in the whole script.
  final int firstWord;

  /// Index just past the last word of this page.
  final int endWord;

  const ScriptPage({
    required this.text,
    required this.firstWord,
    required this.endWord,
  });

  bool contains(int wordIndex) =>
      wordIndex >= firstWord && wordIndex < endWord;
}

/// Paginates a script for the glasses display.
abstract final class ScriptPaginator {
  /// Measured on the hardware: about 25 characters across, 7 lines visible.
  static const int charactersPerLine = 25;
  static const int visibleLines = 7;
  static const int charactersPerPage = charactersPerLine * visibleLines;

  static List<ScriptPage> paginate(
    String script, {
    int budget = charactersPerPage,
  }) {
    final words = script.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];

    final pages = <ScriptPage>[];
    final buffer = StringBuffer();
    var pageStart = 0;

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (buffer.isNotEmpty && buffer.length + word.length + 1 > budget) {
        pages.add(ScriptPage(
          text: buffer.toString(),
          firstWord: pageStart,
          endWord: i,
        ));
        buffer.clear();
        pageStart = i;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word);
    }

    if (buffer.isNotEmpty) {
      pages.add(ScriptPage(
        text: buffer.toString(),
        firstWord: pageStart,
        endWord: words.length,
      ));
    }

    return pages;
  }
}
