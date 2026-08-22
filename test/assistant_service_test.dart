import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/assistant_service.dart';

void main() {
  group('Working out the endpoint', () {
    test('accepts a bare host and port', () {
      expect(
        AssistantService.endpointFor('http://192.168.1.20:11434').toString(),
        'http://192.168.1.20:11434/v1/chat/completions',
      );
    });

    test('assumes http when no scheme is typed', () {
      // People type an address, not a URL.
      expect(
        AssistantService.endpointFor('192.168.1.20:11434').toString(),
        'http://192.168.1.20:11434/v1/chat/completions',
      );
    });

    test('does not double up when /v1 is already there', () {
      expect(
        AssistantService.endpointFor('https://api.example.com/v1').toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('leaves a full path alone', () {
      const full = 'https://api.example.com/v1/chat/completions';
      expect(AssistantService.endpointFor(full).toString(), full);
    });

    test('forgives trailing slashes', () {
      expect(
        AssistantService.endpointFor('http://host:11434///').toString(),
        'http://host:11434/v1/chat/completions',
      );
    });

    test('gives nothing for an empty field', () {
      expect(AssistantService.endpointFor(''), isNull);
      expect(AssistantService.endpointFor('   '), isNull);
    });
  });

  group('Reading the answer', () {
    test('pulls the content out of a chat completion', () {
      final body = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'It is 21 degrees.'},
          },
        ],
      };
      expect(AssistantService.answerFrom(body), 'It is 21 degrees.');
    });

    test('survives a reply shaped differently than expected', () {
      expect(AssistantService.answerFrom({}), isNull);
      expect(AssistantService.answerFrom({'choices': []}), isNull);
      expect(AssistantService.answerFrom({'choices': [{}]}), isNull);
      expect(
        AssistantService.answerFrom({
          'choices': [
            {'message': {'content': 42}},
          ],
        }),
        isNull,
      );
    });
  });

  group('Fitting an answer on the lens', () {
    test('strips the markdown a model insists on producing', () {
      expect(
        AssistantService.shorten('**Yes**, the `answer` is _42_.'),
        'Yes, the answer is 42.',
      );
    });

    test('flattens a list into a line', () {
      expect(
        AssistantService.shorten('- one\n- two\n- three'),
        'one two three',
      );
    });

    test('leaves a short answer as it is', () {
      expect(AssistantService.shorten('  Yes.  '), 'Yes.');
    });

    test('cuts at a sentence when it can', () {
      final long = '${'A sentence that is fairly long. ' * 8}tail';
      final short = AssistantService.shorten(long);
      expect(short.length, lessThanOrEqualTo(AssistantService.maxAnswerLength));
      expect(short.endsWith('.'), isTrue);
    });

    test('never cuts mid-word when there is no sentence to cut at', () {
      final long = 'word ' * 200;
      final short = AssistantService.shorten(long);
      expect(short.length, lessThanOrEqualTo(AssistantService.maxAnswerLength));
      expect(short.endsWith('…'), isTrue);
    });
  });
}
