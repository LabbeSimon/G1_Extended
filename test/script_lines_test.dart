import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/services/teleprompter_tracker.dart';

void main() {
  List<(String, int, int)> describe(List<ScriptLine> lines) =>
      [for (final l in lines) (l.text, l.firstWord, l.endWord)];

  test('wraps on words and counts them for the tracker', () {
    final lines = ScriptLines.wrap('One two three four five six', width: 9);

    expect(describe(lines), [
      ('One two', 0, 2),
      ('three', 2, 3),
      ('four five', 3, 5),
      ('six', 5, 6),
    ]);
  });

  test('a new paragraph starts a new line', () {
    final lines = ScriptLines.wrap('Hi there\n\nNew para', width: 20);

    expect(describe(lines), [('Hi there', 0, 2), ('New para', 2, 4)]);
  });

  test('word indices agree with how the tracker splits the script', () {
    const script = 'A well-known fact — l\'homme le sait.';
    final lines = ScriptLines.wrap(script, width: 12);
    final tracker = TeleprompterTracker(script);

    expect(lines.last.endWord, tracker.words.length);
  });

  test('a word longer than a line is cut rather than overflowing', () {
    final lines = ScriptLines.wrap('abcdefghijkl', width: 5);

    expect(lines.map((l) => l.text), ['abcde', 'fghij', 'kl']);
    expect(lines.last.endWord, 1);
  });

  test('finds the line a reader is on', () {
    final lines = ScriptLines.wrap('One two three four five six', width: 9);

    expect(ScriptLines.lineOf(lines, 0), 0);
    expect(ScriptLines.lineOf(lines, 2), 1);
    expect(ScriptLines.lineOf(lines, 4), 2);
    expect(ScriptLines.lineOf(lines, 6), 3, reason: 'finished: last line');
  });
}
