import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/home_assistant_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('Home Assistant counts once the house is connected', () async {
      final assistant = AssistantService.singleton;
      await assistant.setProvider(AssistantProvider.homeAssistant);
      expect(await assistant.hasCredentials(), isFalse);

      SharedPreferences.setMockInitialValues({
        'assistant_provider': 'ha',
        'home_assistant_enabled': true,
        'home_assistant_base_url': 'http://192.168.1.20:8123',
      });
      FlutterSecureStorage.setMockInitialValues({
        'home_assistant_token': 'a-long-lived-token',
      });
      expect(await assistant.hasCredentials(), isTrue);
    });

    test('the old self-hosted setting falls back to Claude', () async {
      SharedPreferences.setMockInitialValues({'assistant_provider': 'openai'});
      expect(
        await AssistantService.singleton.provider(),
        AssistantProvider.claude,
      );
    });
  });

  group('Which Home Assistant agent answers', () {
    void houseOffers(List<String> agents) {
      HomeAssistantService.clientFactory = () => MockClient((_) async =>
          http.Response(
            jsonEncode([
              for (final id in agents)
                {
                  'entity_id': id,
                  'state': 'unknown',
                  'attributes': {'friendly_name': id.split('.').last},
                },
            ]),
            200,
          ));
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'home_assistant_enabled': true,
        'home_assistant_base_url': 'http://ha.local:8123',
      });
      FlutterSecureStorage.setMockInitialValues({
        'home_assistant_token': 'a-long-lived-token',
      });
      AssistantService.singleton.forgetResolvedAgent();
    });

    tearDown(() => HomeAssistantService.clientFactory = null);

    test('none chosen: the model Home Assistant runs, not its own agent',
        () async {
      houseOffers(['conversation.home_assistant', 'conversation.claude']);
      expect(await AssistantService.singleton.resolvedHaAgent(),
          'conversation.claude');
    });

    test('no model: Home Assistant\'s own agent', () async {
      houseOffers(['conversation.home_assistant']);
      expect(await AssistantService.singleton.resolvedHaAgent(), isNull);
    });

    test('a choice is kept, even the built-in agent', () async {
      houseOffers(['conversation.home_assistant', 'conversation.claude']);
      await AssistantService.singleton
          .setHaAgent(AssistantService.builtInAgent);
      expect(await AssistantService.singleton.resolvedHaAgent(),
          AssistantService.builtInAgent);
    });
  });
}
