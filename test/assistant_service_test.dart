import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/assistant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Reading a Claude reply', () {
    test('takes the first text block', () {
      final body = {
        'content': [
          {'type': 'text', 'text': 'It is 21 degrees.'},
        ],
      };
      expect(AssistantService.claudeAnswerFrom(body), 'It is 21 degrees.');
    });

    test('skips a thinking block and finds the text', () {
      final body = {
        'content': [
          {'type': 'thinking', 'thinking': 'the user asked about weather'},
          {'type': 'text', 'text': 'Sunny and mild.'},
        ],
      };
      expect(AssistantService.claudeAnswerFrom(body), 'Sunny and mild.');
    });

    test('shortens a long answer like any other', () {
      final body = {
        'content': [
          {'type': 'text', 'text': '**Yes**, the `answer` is _42_.'},
        ],
      };
      expect(AssistantService.claudeAnswerFrom(body), 'Yes, the answer is 42.');
    });

    test('is null when there is no usable text', () {
      expect(AssistantService.claudeAnswerFrom({}), isNull);
      expect(AssistantService.claudeAnswerFrom({'content': []}), isNull);
      expect(
        AssistantService.claudeAnswerFrom({
          'content': [
            {'type': 'tool_use', 'name': 'x'},
          ],
        }),
        isNull,
      );
    });
  });

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
      expect(
          AssistantService.answerFrom({
            'choices': [{}]
          }),
          isNull);
      expect(
        AssistantService.answerFrom({
          'choices': [
            {
              'message': {'content': 42}
            },
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

  group('What counts as set up', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('a pasted Claude key is enough, switched on or not', () async {
      final assistant = AssistantService.singleton;
      expect(await assistant.hasCredentials(), isFalse);

      await assistant.setApiKey('sk-ant-test');
      expect(await assistant.hasCredentials(), isTrue);
      expect(await assistant.isConfigured(), isFalse, reason: 'still off');

      await assistant.setEnabled(true);
      expect(await assistant.isConfigured(), isTrue);
    });

    test('a hosted model needs an endpoint and a model', () async {
      final assistant = AssistantService.singleton;
      await assistant.setProvider(AssistantProvider.openAiCompatible);
      await assistant.setBaseUrl('192.168.1.20:11434');
      expect(await assistant.hasCredentials(), isFalse);

      await assistant.setModel('qwen3:4b');
      expect(await assistant.hasCredentials(), isTrue);
    });
  });
}
