import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/home_assistant_service.dart';

/// The house is reached over someone's own network, from a pair of glasses,
/// by a person who typed an address into a phone. Most of what can go wrong
/// is in that address and in the shape of what comes back, so that is what
/// these pin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Working out the address', () {
    Uri? api(String base) => HomeAssistantService.endpointFor(base, '/api/');

    test('accepts a bare host and port, as people actually type it', () {
      expect(api('192.168.1.20:8123').toString(), 'http://192.168.1.20:8123/api/');
    });

    test('keeps https when it was given', () {
      expect(api('https://ha.example.com').toString(),
          'https://ha.example.com/api/');
    });

    test('a trailing slash does not double up', () {
      expect(api('http://ha.local:8123/').toString(), 'http://ha.local:8123/api/');
    });

    test('several trailing slashes are still only one path', () {
      expect(api('http://ha.local:8123///').toString(),
          'http://ha.local:8123/api/');
    });

    test('someone who pasted their dashboard URL still gets there', () {
      expect(api('http://ha.local:8123/lovelace').toString(),
          'http://ha.local:8123/api/');
      expect(api('http://ha.local:8123/config').toString(),
          'http://ha.local:8123/api/');
    });

    test('pasting a URL that already ends in /api does not repeat it', () {
      expect(api('http://ha.local:8123/api').toString(),
          'http://ha.local:8123/api/');
    });

    test('nothing typed is refused rather than guessed at', () {
      expect(api(''), isNull);
      expect(api('   '), isNull);
    });

    test('builds the paths the REST API actually uses', () {
      expect(
        HomeAssistantService.endpointFor('ha.local:8123', '/api/conversation/process')
            .toString(),
        'http://ha.local:8123/api/conversation/process',
      );
      expect(
        HomeAssistantService.endpointFor('ha.local:8123', '/api/states/light.hall')
            .toString(),
        'http://ha.local:8123/api/states/light.hall',
      );
    });
  });

  group('Reading what Home Assistant said', () {
    String reply(String speech) => jsonEncode({
          'response': {
            'speech': {
              'plain': {'speech': speech}
            }
          }
        });

    test('finds the spoken sentence in the nested shape', () {
      expect(HomeAssistantService.speechFrom(reply('Turned on the hall light.')),
          'Turned on the hall light.');
    });

    test('a missing level gives nothing rather than throwing', () {
      expect(HomeAssistantService.speechFrom('{}'), isNull);
      expect(HomeAssistantService.speechFrom(jsonEncode({'response': {}})), isNull);
      expect(
        HomeAssistantService.speechFrom(
            jsonEncode({'response': {'speech': {}}})),
        isNull,
      );
    });

    test('a body that is not JSON at all gives nothing', () {
      expect(HomeAssistantService.speechFrom('<html>502</html>'), isNull);
    });

    test('a speech field of the wrong type gives nothing', () {
      expect(
        HomeAssistantService.speechFrom(jsonEncode({
          'response': {
            'speech': {
              'plain': {'speech': 42}
            }
          }
        })),
        isNull,
      );
    });
  });

  group('Fitting an answer on the lens', () {
    test('a short answer is left alone', () {
      expect(HomeAssistantService.shorten('All lights are off.'),
          'All lights are off.');
    });

    test('newlines and runs of spaces collapse, because the lens has lines',
        () {
      expect(HomeAssistantService.shorten('the hall\n\nlight   is on'),
          'the hall light is on');
    });

    test('a long answer is cut on a sentence boundary, not mid-word', () {
      final long = '${'This is a full sentence. ' * 12}And more after it.';
      final short = HomeAssistantService.shorten(long);

      expect(short.length, lessThanOrEqualTo(220));
      expect(short, endsWith('.'));
    });

    test('a long answer with no sentence end is elided honestly', () {
      final short = HomeAssistantService.shorten('word ' * 100);
      expect(short.length, lessThanOrEqualTo(221));
      expect(short, endsWith('…'));
    });
  });

  group('Understanding an entity', () {
    test('takes the friendly name a person chose in Home Assistant', () {
      final entity = HaEntity.fromMap({
        'entity_id': 'sensor.outside',
        'state': '11.4',
        'attributes': {
          'friendly_name': 'Outside',
          'unit_of_measurement': '°C',
        },
      });

      expect(entity!.friendlyName, 'Outside');
      expect(entity.display, '11.4°C');
      expect(entity.domain, 'sensor');
    });

    test('falls back to the id when nobody named it', () {
      final entity = HaEntity.fromMap({
        'entity_id': 'light.hall',
        'state': 'on',
        'attributes': {},
      });

      expect(entity!.friendlyName, 'light.hall');
      expect(entity.display, 'on');
    });

    test('something that is not an entity is refused', () {
      expect(HaEntity.fromMap(null), isNull);
      expect(HaEntity.fromMap({'state': 'on'}), isNull);
      expect(HaEntity.fromMap({'entity_id': 'no-domain'}), isNull);
    });
  });

  group('Talking to a configured house', () {
    late List<http.Request> sent;

    void answerWith(int status, String body) {
      HomeAssistantService.clientFactory = () => MockClient((request) async {
            sent.add(request);
            return http.Response(body, status,
                headers: {'content-type': 'application/json'});
          });
    }

    setUp(() {
      sent = [];
      SharedPreferences.setMockInitialValues({
        'home_assistant_enabled': true,
        'home_assistant_base_url': 'http://ha.local:8123',
        'home_assistant_lens_entities': ['sensor.outside'],
      });

      // The token lives in the keystore; stand in for it.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'read' ? 'a-long-lived-token' : null,
      );
    });

    tearDown(() {
      HomeAssistantService.clientFactory = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    test('the token is sent as a bearer, which is what HA expects', () async {
      answerWith(200, '{}');
      await HomeAssistantService.singleton.ping();

      expect(sent.single.headers['Authorization'], 'Bearer a-long-lived-token');
    });

    test('a refused token says so, instead of "could not reach"', () async {
      answerWith(401, '{}');
      final result = await HomeAssistantService.singleton.ping();

      expect(result, isA<HaFailure>());
      expect((result as HaFailure).reason, contains('token'));
    });

    test('reaching the wrong path is named as such', () async {
      answerWith(404, '');
      final result = await HomeAssistantService.singleton.ping();

      expect((result as HaFailure).reason, contains('address'));
    });

    test('a sentence goes to the conversation agent as text', () async {
      answerWith(
        200,
        jsonEncode({
          'response': {
            'speech': {
              'plain': {'speech': 'Turned it off.'}
            }
          }
        }),
      );

      final result =
          await HomeAssistantService.singleton.converse('turn off the hall light');

      expect(result, isA<HaOk>());
      expect((result as HaOk).text, 'Turned it off.');
      expect(sent.single.url.path, '/api/conversation/process');
      expect(jsonDecode(sent.single.body)['text'], 'turn off the hall light');
    });

    test('an agent with nothing to say is a failure, not an empty lens',
        () async {
      answerWith(200, '{}');
      final result = await HomeAssistantService.singleton.converse('hello');
      expect(result, isA<HaFailure>());
    });

    test('the chosen entities become lens notes', () async {
      answerWith(
        200,
        jsonEncode({
          'entity_id': 'sensor.outside',
          'state': '11.4',
          'attributes': {
            'friendly_name': 'Outside',
            'unit_of_measurement': '°C',
          },
        }),
      );

      final notes =
          await HomeAssistantService.singleton.generateDashboardItems();

      expect(notes, hasLength(1));
      expect(notes.single.name, 'Outside');
      expect(notes.single.text, '11.4°C');
    });

    test('an entity that cannot be read is left out, not shown as an error',
        () async {
      answerWith(404, '');
      expect(await HomeAssistantService.singleton.generateDashboardItems(),
          isEmpty);
    });

    test('nothing is fetched at all when it is switched off', () async {
      SharedPreferences.setMockInitialValues({
        'home_assistant_enabled': false,
        'home_assistant_base_url': 'http://ha.local:8123',
        'home_assistant_lens_entities': ['sensor.outside'],
      });
      answerWith(200, '{}');

      expect(await HomeAssistantService.singleton.generateDashboardItems(),
          isEmpty);
      expect(sent, isEmpty, reason: 'a disabled integration must not phone home');
    });
  });
}
