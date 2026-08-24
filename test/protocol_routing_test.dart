import 'package:flutter_test/flutter_test.dart';

import 'package:g1_extended/models/g1/commands.dart';
import 'package:g1_extended/models/g1/notification.dart';

/// Notifications and the allowlist go to both arms — the document names
/// 0x4B and 0x04 as left-arm commands, but that turned out to be wrong: the
/// reference implementations send both to both temples.
///
/// The header these pin is the four-byte one — command, notifyId, chunk
/// count, index — as Fahrplan and even_glasses send it to real glasses.
/// The repo this app was forked from had lost the notifyId byte, which
/// shifted every field the firmware reads and made it discard the whole
/// notification silently; an earlier version of this test pinned that
/// broken three-byte shape as though it were the specification.
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
        expect(chunks[i][1], 1,
            reason: 'chunk $i is missing the notifyId byte');
        expect(chunks[i][2], chunks.length,
            reason: 'chunk $i misreports how many there are');
        expect(chunks[i][3], i, reason: 'chunk $i is misnumbered');
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
        payload.addAll(chunk.sublist(4));
      }
      expect(String.fromCharCodes(payload), contains('w299'),
          reason: 'the tail of the message was lost in the chunking');
    });
  });
}
