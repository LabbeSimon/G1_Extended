import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/notification.dart';

/// Notifications and the allowlist go to both arms — the document names
/// 0x4B and 0x04 as left-arm commands, but that turned out to be wrong: the
/// reference implementation this app was forked from sends both to both
/// temples, and trusting the document over it broke delivery outright.
/// These pin the header shape 0x4B actually uses, which the document did
/// get right.
void main() {
  NCSNotification sample({String message = 'hello'}) => NCSNotification(
        msgId: 1,
        action: 0,
        type: 0,
        appIdentifier: 'org.example',
        title: 'Title',
        subtitle: '',
        message: message,
        displayName: 'Example',
      );

  group('The 0x4B header, as documented', () {
    test('every chunk starts with the command, the count and its index',
        () async {
      final chunks =
          await G1Notification(ncsNotification: sample()).constructNotification();

      expect(chunks, isNotEmpty);
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i][0], Commands.NOTIFICATION,
            reason: 'chunk $i does not announce itself as 0x4B');
        expect(chunks[i][1], chunks.length,
            reason: 'chunk $i misreports how many there are');
        expect(chunks[i][2], i, reason: 'chunk $i is misnumbered');
      }
    });

    test('no chunk exceeds the 180 byte limit the document states', () async {
      final long = 'x' * 4000;
      final chunks = await G1Notification(ncsNotification: sample(message: long))
          .constructNotification();

      expect(chunks.length, greaterThan(1),
          reason: 'a long notification must be split');
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(180));
      }
    });

    test('the payload reassembles into the whole message', () async {
      final long = List.generate(300, (i) => 'w$i').join(' ');
      final chunks = await G1Notification(ncsNotification: sample(message: long))
          .constructNotification();

      final payload = <int>[];
      for (final chunk in chunks) {
        payload.addAll(chunk.sublist(3));
      }
      expect(String.fromCharCodes(payload), contains('w299'),
          reason: 'the tail of the message was lost in the chunking');
    });
  });
}
