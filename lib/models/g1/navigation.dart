import 'dart:convert';
import 'dart:typed_data';

/// The glasses' own navigation screen, command 0x0A: a turn arrow from the
/// glasses' built-in set, the distance to it, the road, and the trip's
/// remaining time and distance.
///
/// The official app drives it from its own route; this app drives it from
/// the navigation app's notification. Frames as the official Even app 1.6.5
/// builds them; see docs/protocol/notes-notifications-dashboard-navigation.md,
/// section 7.
abstract final class NavigationProtocol {
  static const int command = 0x0A;
  static const int startSub = 0x00;
  static const int routeSub = 0x01;
  static const int heartbeatSub = 0x04;
  static const int exitSub = 0x05;
  static const int arriveSub = 0x06;

  /// Opens the navigation screen: `0A 06 00 seq 00 01`.
  static Uint8List start({required int seq}) => _short(seq, startSub, 0x01);

  /// Keeps the screen alive; the official app sends one a second, to the
  /// right temple only.
  static Uint8List heartbeat({required int seq, required int beat}) =>
      _short(seq, heartbeatSub, beat);

  /// Closes the navigation screen: `0A 06 00 seq 05 01`.
  static Uint8List exit({required int seq}) => _short(seq, exitSub, 0x01);

  /// What the screen shows. [x] and [y] place the position on the overview
  /// map, which this app does not send, so they stay at zero.
  static Uint8List route({
    required int seq,
    required int icon,
    int x = 0,
    int y = 0,
    String remainingTime = '',
    String remainingDistance = '',
    String roadName = '',
    String nextDirectionDistance = '',
    String speed = '',
  }) =>
      _framed(seq, routeSub, [
        icon & 0xFF,
        x & 0xFF,
        (x >> 8) & 0xFF,
        y & 0xFF,
        (y >> 8) & 0xFF,
        ...field(remainingTime, 23),
        ...field(remainingDistance, 23),
        ...field(roadName, 63),
        ...field(nextDirectionDistance, 23),
        ...field(speed, 23),
      ]);

  /// The arrival message: flag 2 when the trip is complete, 1 when the
  /// destination has been reached.
  static Uint8List arrive({
    required int seq,
    required String text,
    bool complete = false,
  }) =>
      _framed(seq, arriveSub, [complete ? 2 : 1, ...utf8.encode(text), 0x00]);

  /// The answer the official app waits for: same command, sequence and
  /// sub-command. Anything but an explicit failure, 0xCA, counts as taken.
  static bool accepts(List<int> reply, Uint8List sent) =>
      reply.length >= 6 &&
      reply[0] == command &&
      reply[3] == sent[3] &&
      reply[4] == sent[4] &&
      reply[5] != 0xCA;

  /// UTF-8 cut to [max] bytes with an ellipsis, as the official app does,
  /// never mid-character, then the zero that ends the field.
  static List<int> field(String text, int max) {
    var bytes = utf8.encode(text.trim());
    if (bytes.length > max) {
      var runes = text.trim().runes.toList();
      do {
        runes = runes.sublist(0, runes.length - 1);
        bytes = utf8.encode('${String.fromCharCodes(runes).trimRight()}…');
      } while (bytes.length > max && runes.isNotEmpty);
    }
    return [...bytes, 0x00];
  }

  static Uint8List _short(int seq, int sub, int value) => Uint8List.fromList(
      [command, 0x06, 0x00, seq % 255, sub, value & 0xFF]);

  static Uint8List _framed(int seq, int sub, List<int> body) {
    final length = 5 + body.length;
    return Uint8List.fromList([
      command,
      length & 0xFF,
      (length >> 8) & 0xFF,
      seq % 255,
      sub,
      ...body,
    ]);
  }
}

/// The glasses' built-in turn arrows, by the index the official app sends.
///
/// The official app maps each Mapbox turn icon to one of these; this app
/// reads the navigation app's wording instead, in French or English.
abstract final class NavigationIcon {
  static const int unknown = 1;
  static const int straight = 2;
  static const int right = 3;
  static const int left = 4;
  static const int slightRight = 5;
  static const int slightLeft = 6;
  static const int sharpRight = 7;
  static const int sharpLeft = 8;
  static const int uTurnCounterclockwise = 9;
  static const int uTurnClockwise = 10;
  static const int merge = 11;
  static const int roundaboutCounterclockwise = 28;
  static const int roundaboutClockwise = 29;
  static const int mergeRight = 32;
  static const int mergeLeft = 33;
  static const int forkRight = 34;
  static const int forkLeft = 35;

  /// The arrow for an instruction. [leftHandTraffic] turns roundabouts and
  /// U-turns the other way round. Most specific wording first: "slightly
  /// right" must not read as "right", nor a roundabout exit as an exit.
  static int forInstruction(String instruction, {bool leftHandTraffic = false}) {
    final text = plain(instruction);
    bool says(List<String> words) => words.any(text.contains);

    if (says(['demi-tour', 'demi tour', 'u-turn', 'u turn'])) {
      return leftHandTraffic ? uTurnClockwise : uTurnCounterclockwise;
    }
    if (says(['rond-point', 'rond point', 'giratoire', 'roundabout',
        'traffic circle', 'rotary'])) {
      return leftHandTraffic ? roundaboutClockwise : roundaboutCounterclockwise;
    }
    if (says(['legerement a droite', 'slight right', 'slightly right',
        'bear right'])) {
      return slightRight;
    }
    if (says(['legerement a gauche', 'slight left', 'slightly left',
        'bear left'])) {
      return slightLeft;
    }
    if (says(['fortement a droite', 'sharp right'])) return sharpRight;
    if (says(['fortement a gauche', 'sharp left'])) return sharpLeft;
    if (says(['restez a droite', 'serrez a droite', 'gardez la droite',
        'tenez la droite', 'keep right'])) {
      return forkRight;
    }
    if (says(['restez a gauche', 'serrez a gauche', 'gardez la gauche',
        'tenez la gauche', 'keep left'])) {
      return forkLeft;
    }
    if (says(['inserez', 'rejoignez', 'merge'])) {
      if (says(['droite', 'right'])) return mergeRight;
      if (says(['gauche', 'left'])) return mergeLeft;
      return merge;
    }
    if (says(['sortie', 'bretelle', 'take the exit', 'take exit', 'ramp'])) {
      return slightRight;
    }
    if (says(['a droite', 'right'])) return right;
    if (says(['a gauche', 'left'])) return left;
    if (says(['tout droit', 'continuez', 'continue', 'straight', 'head '])) {
      return straight;
    }
    return unknown;
  }

  /// Lower case, French accents removed, so wording matches either way.
  static String plain(String text) {
    const from = 'àâäáéèêëíìîïóòôöúùûüçœ';
    const to = 'aaaaeeeeiiiioooouuuuco';
    final buffer = StringBuffer();
    for (final char in text.toLowerCase().split('')) {
      final i = from.indexOf(char);
      buffer.write(i < 0 ? char : to[i]);
    }
    return buffer.toString();
  }
}

/// One turn instruction, read from a navigation app's notification.
class NavigationRoute {
  const NavigationRoute({
    required this.icon,
    this.distance = '',
    this.road = '',
    this.arrived = false,
  });

  final int icon;

  /// Distance to the turn, as the app wrote it: "200 m", "1,2 km".
  final String distance;

  /// The road, or failing that the instruction itself.
  final String road;

  /// The navigation app says the trip is over.
  final bool arrived;

  /// Reads the notification's two fields, whichever holds what.
  static NavigationRoute? parse(
    String? title,
    String? content, {
    bool leftHandTraffic = false,
  }) {
    final first = title?.trim() ?? '';
    final second = content?.trim() ?? '';
    final both = '$first $second'.trim();
    if (both.isEmpty) return null;

    final plain = NavigationIcon.plain(both);
    final arrived = [
      'vous etes arrive',
      'destination atteinte',
      'you have arrived',
      "you've arrived",
      'arrived at',
    ].any(plain.contains);

    final distance = RegExp(
      r'(\d+(?:[.,]\d+)?)\s?(km|m|mi|ft|yd)\b',
      caseSensitive: false,
    ).firstMatch(both);

    // The road is whichever field is not just the distance.
    final distanceOnly = RegExp(r'^\s*(dans\s+|in\s+)?\d+(?:[.,]\d+)?\s?(km|m|mi|ft|yd)\s*$',
        caseSensitive: false);
    final road = [second, first]
        .firstWhere((f) => f.isNotEmpty && !distanceOnly.hasMatch(f),
            orElse: () => '');

    return NavigationRoute(
      icon: NavigationIcon.forInstruction(both, leftHandTraffic: leftHandTraffic),
      distance:
          distance == null ? '' : '${distance.group(1)} ${distance.group(2)}',
      road: road,
      arrived: arrived,
    );
  }
}
