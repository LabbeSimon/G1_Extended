import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/dashboard_panel.dart';
import 'package:g1_extended/models/g1/glasses_settings.dart';

void main() {
  group('The outer packet', () {
    test('is the one this app already sends for the layout', () {
      // The layout command was here long before the panes were understood.
      // If the framing worked out from even-utils is right, rebuilding that
      // known-good packet from it must land on the same bytes — which is
      // the only part of this file that can be checked without glasses.
      final rebuilt = DashboardPanel.frame(0x08, [0x06, 0x00, 0x00]);

      expect(rebuilt, [
        ...DashboardLayout.DASHBOARD_CHANGE_COMMAND,
        ...DashboardLayout.DASHBOARD_FULL,
      ]);
    });

    test('carries its own length, header included', () {
      final packet = DashboardPanel.frame(0x80, List.filled(10, 0xAA));

      expect(packet[0], 0x06);
      expect(packet[1] | (packet[2] << 8), packet.length);
      expect(packet[3], 0x80);
    });

    test('counts chunks from one and walks the sync id', () {
      final packets = DashboardPanel.split(
        DashboardPanel.newsSubcommand,
        List.filled(400, 0x01),
      );

      expect(packets.length, 3); // 180 + 180 + 40
      expect(packets.first[3], DashboardPanel.firstSyncId);
      expect(packets.last[3], DashboardPanel.firstSyncId + 2);
      // Sub-command, then total and index as two little-endian shorts.
      expect(packets.first.sublist(4, 9), [0x05, 3, 0, 1, 0]);
      expect(packets.last.sublist(4, 9), [0x05, 3, 0, 3, 0]);
    });
  });

  group('News', () {
    test('a card is source then text, each with its own length', () {
      final packets = DashboardNews.write(
        mode: DashboardMode.dual,
        slot: 1,
        card: NewsCard(source: 'BBC', text: 'hello'),
      );

      expect(packets.length, 1);
      expect(packets.single, [
        0x06, 0x1B, 0x00, 0x80, // 06, length 27, sync id
        0x05, 0x01, 0x00, 0x01, 0x00, // news, one packet, packet one
        0x01, // dual
        0x02, // the news pane
        0x02, // showing news
        0x01, // slot one
        0x01, // update
        0x01, 0x03, 0x42, 0x42, 0x43, // source, 3 bytes, "BBC"
        0x02, 0x05, 0x00, 0x68, 0x65, 0x6C, 0x6C, 0x6F, // text, 5, "hello"
      ]);
    });

    test('a long source is cut on a character, not in the middle of one', () {
      final card = NewsCard(source: 'é' * 40, text: 'x');
      final encoded = card.encode();

      // Forty accented characters are eighty bytes, over the sixty-four the
      // field holds. Thirty-two survive whole; a byte-wise cut would leave
      // half an accent and make the field unreadable.
      expect(encoded[1], 64);
      expect(
        String.fromCharCodes(encoded.sublist(2, 66)),
        isNot(contains('�')),
      );
    });

    test('slots run from one to four', () {
      expect(
        () => DashboardNews.write(mode: DashboardMode.dual, slot: 0),
        throwsArgumentError,
      );
      expect(
        () => DashboardNews.write(mode: DashboardMode.dual, slot: 5),
        throwsArgumentError,
      );
    });

    test('clearing a slot sends the delete operation and no card', () {
      final packet =
          DashboardNews.clear(mode: DashboardMode.full, slot: 2).single;

      expect(packet.sublist(9), [
        0x00, // full
        0x02, // news pane
        0x01, // nothing selected
        0x02, // slot two
        0x02, // delete
      ]);
    });
  });

  group('Map', () {
    test('the pane is wider in dual than in full', () {
      expect(DashboardMap.widthFor(DashboardMode.dual), 376);
      expect(DashboardMap.widthFor(DashboardMode.full), 296);
      expect(DashboardMap.imageBytesFor(DashboardMode.dual), 6392);
      expect(DashboardMap.imageBytesFor(DashboardMode.full), 5032);
    });

    test('an image of the wrong size is refused rather than sent', () {
      expect(
        () => DashboardMap.image(
          mode: DashboardMode.dual,
          packed: Uint8List(100),
        ),
        throwsArgumentError,
      );
    });

    test('a full pane goes out in thirty-six packets', () {
      final packets = DashboardMap.image(
        mode: DashboardMode.dual,
        packed: Uint8List(DashboardMap.imageBytesFor(DashboardMode.dual)),
      );

      // Four header bytes plus 6392 of image, cut at 180.
      expect(packets.length, 36);
      expect(packets.first[4], DashboardPanel.mapSubcommand);
      expect(packets.first.sublist(9, 13), [
        0x01, // dual
        0x04, // the navigation pane, which the firmware calls citywalk
        0x02, // updating the map
        0x01,
      ]);
    });

    test('the cursor is one packet with its position in front', () {
      final packet = DashboardMap.cursor(
        mode: DashboardMode.dual,
        x: 300,
        y: 12,
        packed: Uint8List(32 * 32 ~/ 8),
      );

      expect(packet.sublist(9, 15), [
        0x01, // dual
        0x04, // navigation pane
        0x03, // showing the map
        0x2C, 0x01, // x = 300, little endian
        0x0C, // y = 12
      ]);
      expect(packet[15], 0x00);
    });
  });

  group('The test chart', () {
    test('weighs exactly what the pane holds', () {
      for (final mode in [DashboardMode.dual, DashboardMode.full]) {
        expect(
          DashboardMap.testPattern(mode).length,
          DashboardMap.imageBytesFor(mode),
        );
      }
    });

    test('lights the corners and marks the bit order', () {
      final packed = DashboardMap.testPattern(DashboardMode.dual);

      // The whole first row is the border, so every bit of its bytes is set.
      expect(packed[0], 0xFF);
      // The fourth row starts with three pixels and nothing else until the
      // far edge: 0b00000111 if the low bit leads.
      const rowBytes = 376 ~/ 8;
      expect(packed[3 * rowBytes], 0x07);
    });
  });

  group('Packing', () {
    test('the first pixel of a row is the low bit of its byte', () {
      // Not how a BMP stores it, and the reason a bitmap that displays fine
      // through 0x15 comes out as noise in this pane.
      final pixels = Uint8List(16 * 8);
      pixels[0] = 1;
      final packed = DashboardMap.pack(pixels, width: 16, height: 8);

      expect(packed[0], 0x01);
    });

    test('the eighth pixel is the high bit, the ninth the next byte', () {
      final pixels = Uint8List(16 * 8);
      pixels[7] = 1;
      pixels[8] = 1;
      final packed = DashboardMap.pack(pixels, width: 16, height: 8);

      expect(packed[0], 0x80);
      expect(packed[1], 0x01);
    });

    test('rows follow each other without padding', () {
      final pixels = Uint8List(16 * 8);
      pixels[16] = 1; // first pixel of the second row
      final packed = DashboardMap.pack(pixels, width: 16, height: 8);

      expect(packed[2], 0x01);
      expect(packed.length, 16);
    });

    test('a width that is not a multiple of eight is refused', () {
      expect(
        () => DashboardMap.pack(Uint8List(30), width: 10, height: 3),
        throwsArgumentError,
      );
    });
  });
}
