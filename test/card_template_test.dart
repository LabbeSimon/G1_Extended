import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/card_template.dart';

void main() {
  group('Filling a template', () {
    test('replaces a known token', () {
      expect(
        CardTemplate.render('It is {time}', {'time': '14:03'}),
        'It is 14:03',
      );
    });

    test('replaces several tokens in one line', () {
      expect(
        CardTemplate.render(
          '{day} {date} · {temp}',
          {'day': 'Sat', 'date': '22 Aug', 'temp': '21°'},
        ),
        'Sat 22 Aug · 21°',
      );
    });

    test('leaves an unknown token visible instead of deleting it', () {
      // A typo that vanishes silently leaves a gap nobody can explain.
      expect(
        CardTemplate.render('Hello {nmae}', {'name': 'Simon'}),
        'Hello {nmae}',
      );
    });

    test('shows a dash for a known token with nothing behind it yet', () {
      expect(CardTemplate.render('{temp}', {'temp': null}), '--');
      expect(CardTemplate.render('{temp}', {'temp': ''}), '--');
    });

    test('ignores braces that are not tokens', () {
      expect(
        CardTemplate.render('a { b } {Time} {1x}', {'time': '9:00'}),
        'a { b } {Time} {1x}',
      );
    });

    test('handles a template with no tokens at all', () {
      expect(CardTemplate.render('Just text', {}), 'Just text');
    });

    test('lists the tokens that will never be filled', () {
      expect(
        CardTemplate.unknownTokens('{time} {nmae} {temp} {nmae}'),
        ['nmae'],
      );
      expect(CardTemplate.unknownTokens('{time} {temp}'), isEmpty);
    });
  });

  group('Reading a value out of a source', () {
    test('walks a dotted path', () {
      final json = {
        'main': {'temp': 21.5},
      };
      expect(CardSource.extract(json, 'main.temp'), '21.5');
    });

    test('indexes into a list', () {
      final json = {
        'list': [
          {'name': 'first'},
          {'name': 'second'},
        ],
      };
      expect(CardSource.extract(json, 'list.1.name'), 'second');
    });

    test('gives nothing for a path that does not exist', () {
      expect(CardSource.extract({'a': 1}, 'b'), isNull);
      expect(CardSource.extract({'a': 1}, 'a.b.c'), isNull);
      expect(CardSource.extract({'list': []}, 'list.3'), isNull);
    });

    test('refuses to render a whole object onto the lens', () {
      expect(CardSource.extract({'a': {'b': 1}}, 'a'), isNull);
      expect(CardSource.extract({'a': [1, 2]}, 'a'), isNull);
    });

    test('takes the document itself when no path is given', () {
      expect(CardSource.extract('plain text', null), 'plain text');
      expect(CardSource.extract(42, ''), '42');
    });

    test('collapses whitespace so a note stays on one line', () {
      expect(CardSource.clamp('  hello \n  world  '), 'hello world');
    });

    test('shortens a value too long for the lens', () {
      final long = 'x' * 200;
      final clamped = CardSource.clamp(long);
      expect(clamped.length, CardSource.maxLength);
      expect(clamped.endsWith('…'), isTrue);
    });

    test('leaves a short value untouched', () {
      expect(CardSource.clamp('21°C'), '21°C');
    });
  });
}
