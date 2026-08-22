import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/teleprompter_tracker.dart';

const script =
    'Good evening everyone and thank you for coming tonight. '
    'We are here to talk about something that matters. '
    'The first point is simple and the second one is harder. '
    'Let us begin with the simple one.';

void main() {
  group('Following a reader', () {
    test('starts at the beginning', () {
      final tracker = TeleprompterTracker(script);
      expect(tracker.position, 0);
      expect(tracker.progress, 0);
    });

    test('advances past the words that were spoken', () {
      final tracker = TeleprompterTracker(script);
      final moved = tracker.feed('good evening everyone and thank you');
      expect(moved, isNotNull);
      expect(tracker.position, greaterThan(0));
    });

    test('survives a misheard word', () {
      final tracker = TeleprompterTracker(script);
      // "thang" instead of "thank": exact matching would stall here.
      tracker.feed('good evening everyone and thang you');
      expect(tracker.position, greaterThan(0));
    });

    test('ignores a phrase it cannot place', () {
      final tracker = TeleprompterTracker(script);
      expect(tracker.feed('completely unrelated gibberish here'), isNull);
      expect(tracker.position, 0);
    });

    test('never drags the reader backwards', () {
      final tracker = TeleprompterTracker(script);
      tracker.feed('the first point is simple');
      final advanced = tracker.position;

      // The recogniser repeating an earlier sentence must not rewind.
      tracker.feed('good evening everyone');
      expect(tracker.position, greaterThanOrEqualTo(advanced));
    });

    test('does not move on a single common word', () {
      final tracker = TeleprompterTracker(script);
      expect(tracker.feed('the'), isNull);
      expect(tracker.position, 0);
    });

    test('only looks at the tail of a long transcript', () {
      final tracker = TeleprompterTracker(script);
      // Vosk resends the whole sentence as it refines it; the reader is at
      // the end of it, not the start.
      tracker.feed('good evening everyone and thank you for coming tonight '
          'we are here to talk about something that matters');
      expect(tracker.position, greaterThan(10));
    });

    test('reaches the end and says so', () {
      final tracker = TeleprompterTracker(script);
      tracker.seek(tracker.words.length);
      expect(tracker.isFinished, isTrue);
      expect(tracker.progress, 1);
    });

    test('handles an empty script without complaint', () {
      final tracker = TeleprompterTracker('');
      expect(tracker.feed('anything'), isNull);
      expect(tracker.isFinished, isTrue);
    });

    test('ignores punctuation the recogniser never produces', () {
      final tracker = TeleprompterTracker('Hello, world! This is: a test.');
      tracker.feed('hello world this is');
      expect(tracker.position, greaterThan(0));
    });
  });

  group('Paginating for the lens', () {
    test('never splits a word across pages', () {
      final pages = ScriptPaginator.paginate(script, budget: 40);
      for (final page in pages) {
        expect(page.text.length, lessThanOrEqualTo(40));
        expect(page.text.trim(), page.text);
      }
    });

    test('covers every word exactly once, in order', () {
      final pages = ScriptPaginator.paginate(script, budget: 40);
      expect(pages.first.firstWord, 0);
      for (var i = 1; i < pages.length; i++) {
        expect(pages[i].firstWord, pages[i - 1].endWord);
      }
      expect(pages.last.endWord, script.trim().split(RegExp(r'\s+')).length);
    });

    test('locates which page a word is on', () {
      final pages = ScriptPaginator.paginate(script, budget: 40);
      final page = pages.firstWhere((p) => p.contains(0));
      expect(page, pages.first);
      expect(pages.first.contains(pages.first.endWord), isFalse);
    });

    test('gives nothing for an empty script', () {
      expect(ScriptPaginator.paginate('   '), isEmpty);
    });

    test('keeps a single long word rather than losing it', () {
      final pages = ScriptPaginator.paginate('supercalifragilistic', budget: 5);
      expect(pages, hasLength(1));
      expect(pages.first.text, 'supercalifragilistic');
    });
  });
}
