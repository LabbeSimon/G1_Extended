import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/navigation.dart';

/// The glasses' navigation screen, frame by frame, as the official app 1.6.5
/// builds it (docs/protocol/notes-notifications-dashboard-navigation.md).
void main() {
  group('Frames', () {
    test('open, heartbeat and close are six bytes', () {
      expect(NavigationProtocol.start(seq: 7), [0x0A, 0x06, 0x00, 7, 0x00, 0x01]);
      expect(NavigationProtocol.heartbeat(seq: 8, beat: 3),
          [0x0A, 0x06, 0x00, 8, 0x04, 3]);
      expect(NavigationProtocol.exit(seq: 300), [0x0A, 0x06, 0x00, 45, 0x05, 0x01]);
    });

    test('a route carries the icon, the position and five strings', () {
      final frame = NavigationProtocol.route(
        seq: 1,
        icon: NavigationIcon.right,
        x: 0x0102,
        y: 3,
        roadName: 'Rue de la Paix',
        nextDirectionDistance: '200 m',
        speed: '48 km/h',
      );

      expect(frame.sublist(0, 10),
          [0x0A, frame.length & 0xFF, frame.length >> 8, 1, 0x01, 3, 0x02, 0x01, 3, 0]);
      final strings = utf8.decode(frame.sublist(10)).split('\u0000');
      expect(strings.take(5), ['', '', 'Rue de la Paix', '200 m', '48 km/h']);
    });

    test('long fields are cut with an ellipsis, never mid-character', () {
      final road = NavigationProtocol.field('Avenue de la République française ' * 3, 63);
      expect(road.length, lessThanOrEqualTo(64));
      expect(road.last, 0);
      expect(utf8.decode(road.sublist(0, road.length - 1)), endsWith('…'));
    });

    test('arrival carries its flag and text', () {
      expect(NavigationProtocol.arrive(seq: 2, text: 'OK'),
          [0x0A, 9, 0x00, 2, 0x06, 1, 0x4F, 0x4B, 0]);
    });

    test('a reply counts unless it says 0xCA', () {
      final sent = NavigationProtocol.start(seq: 5);
      expect(NavigationProtocol.accepts([0x0A, 6, 0, 5, 0, 0xC9], sent), isTrue);
      expect(NavigationProtocol.accepts([0x0A, 6, 0, 5, 0, 0xCA], sent), isFalse);
      expect(NavigationProtocol.accepts([0x0A, 6, 0, 6, 0, 0xC9], sent), isFalse,
          reason: 'another exchange');
    });
  });

  group('Arrows from the wording', () {
    int icon(String text, {bool left = false}) =>
        NavigationIcon.forInstruction(text, leftHandTraffic: left);

    test('French', () {
      expect(icon('Tournez à droite vers Rue de la Paix'), NavigationIcon.right);
      expect(icon('Tournez à gauche'), NavigationIcon.left);
      expect(icon('Prenez légèrement à gauche'), NavigationIcon.slightLeft);
      expect(icon('Tournez fortement à droite'), NavigationIcon.sharpRight);
      expect(icon('Au rond-point, prenez la 2e sortie'),
          NavigationIcon.roundaboutCounterclockwise);
      expect(icon('Faites demi-tour'), NavigationIcon.uTurnCounterclockwise);
      expect(icon('Restez à droite'), NavigationIcon.forkRight);
      expect(icon('Prenez la sortie 12'), NavigationIcon.slightRight);
      expect(icon('Insérez-vous à gauche'), NavigationIcon.mergeLeft);
      expect(icon('Continuez tout droit'), NavigationIcon.straight);
    });

    test('English', () {
      expect(icon('Turn left onto Main St'), NavigationIcon.left);
      expect(icon('Slight right'), NavigationIcon.slightRight);
      expect(icon('Keep left at the fork'), NavigationIcon.forkLeft);
      expect(icon('Make a U-turn'), NavigationIcon.uTurnCounterclockwise);
    });

    test('driving on the left turns roundabouts and U-turns around', () {
      expect(icon('At the roundabout, take the 1st exit', left: true),
          NavigationIcon.roundaboutClockwise);
      expect(icon('Make a U-turn', left: true), NavigationIcon.uTurnClockwise);
    });

    test('anything else is the plain arrow', () {
      expect(icon('Rue de Rivoli'), NavigationIcon.unknown);
    });
  });

  group('Reading a notification', () {
    test('distance in one field, instruction in the other', () {
      final route = NavigationRoute.parse('200 m', 'Tournez à droite vers Rue de la Paix')!;
      expect(route.icon, NavigationIcon.right);
      expect(route.distance, '200 m');
      expect(route.road, 'Tournez à droite vers Rue de la Paix');
      expect(route.arrived, isFalse);
    });

    test('a decimal distance with a comma', () {
      expect(NavigationRoute.parse('Dans 1,2 km', 'Restez à gauche')!.distance,
          '1,2 km');
    });

    test('arrival', () {
      expect(NavigationRoute.parse('Vous êtes arrivé', '12 Rue X')!.arrived, isTrue);
    });

    test('nothing to read is nothing', () {
      expect(NavigationRoute.parse(null, '  '), isNull);
    });
  });

  test('frames are bytes', () {
    expect(NavigationProtocol.start(seq: 0), isA<Uint8List>());
  });
}
