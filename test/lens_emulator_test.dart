import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/dashboard.dart';
import 'package:g1_extended/models/g1/lens_framebuffer.dart';
import 'package:g1_extended/models/g1/notification.dart';
import 'package:g1_extended/models/g1/text.dart';
import 'package:g1_extended/services/lens_emulator.dart';

/// The mirror is fed by the app's own senders, never by hand-written bytes.
///
/// A test that invents its packets proves the decoder agrees with the test,
/// which is worth nothing. Building them with [TextMessage] and
/// [G1Notification] proves the decoder agrees with what the temples receive,
/// so the day a builder changes, this fails instead of the wearer noticing.
void main() {
  group('Text', () {
    test('a one-page message arrives whole', () {
      final emulator = LensEmulator();
      for (final packet in TextMessage('bonjour').constructSendText()) {
        emulator.consume(packet);
      }

      expect(emulator.state.surface, LensSurface.text);
      expect(emulator.state.text.trim(), 'bonjour');
      expect(emulator.state.maxPages, 1);
    });

    test('pagination is reported as the glasses were told it', () {
      // Five lines per page, and the app wraps at twenty characters, so this
      // is comfortably more than one screen.
      final long = List.filled(40, 'alpha bravo').join(' ');
      final emulator = LensEmulator();
      for (final packet in TextMessage(long).constructSendText()) {
        emulator.consume(packet);
      }

      expect(emulator.state.maxPages, greaterThan(1));
      expect(emulator.state.page, emulator.state.maxPages);
    });

    test('lines are cut at the width the lens actually has', () {
      // Forty characters, not twenty: half a panel is what the fork this
      // app came from was using, and it doubled the page count for nothing.
      final long = List.filled(20, 'alpha bravo charlie').join(' ');
      final emulator = LensEmulator();
      for (final packet in TextMessage(long).constructSendText()) {
        emulator.consume(packet);
      }

      for (final line in emulator.state.text.split('\n')) {
        expect(line.length, lessThanOrEqualTo(TextMessage.charsPerLine));
      }
      expect(
        emulator.state.text.split('\n').any((line) => line.length > 20),
        isTrue,
        reason: 'a line should now use the width past twenty characters',
      );
    });

    test('the screen status byte is kept raw', () {
      final packets = TextMessage('salut').constructSendText();
      final emulator = LensEmulator()..consume(packets.first);

      // Whatever the app decided to send, the mirror shows. Today that is
      // 0x30: AIStatus.DISPLAYING (0x20) | ScreenAction.NEW_CONTENT (0x10).
      // Worth a look on the glasses — the community spec reads the low
      // nibble as the action (NEW_CONTENT = 0x01) and the high one as the
      // mode, which would make this byte 0x31, or 0x71 for plain text.
      expect(emulator.state.screenStatus, packets.first[4]);
    });
  });

  group('Notification', () {
    test('chunks are reassembled into the document that was sent', () async {
      final notification = G1Notification(
        ncsNotification: NCSNotification(
          msgId: 1,
          appIdentifier: 'fr.simonlabbe.g1extended',
          title: 'Marco',
          subtitle: '',
          message: 'on se voit a 20h',
          displayName: 'Messages',
        ),
      );

      final emulator = LensEmulator();
      for (final chunk in await notification.constructNotification()) {
        emulator.consume(chunk);
      }

      expect(emulator.state.surface, LensSurface.notification);
      final body = emulator.state.notification?['ncs_notification']
          as Map<String, dynamic>?;
      expect(body?['title'], 'Marco');
      expect(body?['message'], 'on se voit a 20h');
    });

    test('a long message spans several chunks and still parses', () async {
      final notification = G1Notification(
        ncsNotification: NCSNotification(
          msgId: 2,
          appIdentifier: 'fr.simonlabbe.g1extended',
          title: 'Long',
          subtitle: '',
          message: 'x' * 600,
          displayName: 'Messages',
        ),
      );

      final chunks = await notification.constructNotification();
      expect(chunks.length, greaterThan(1));

      final emulator = LensEmulator();
      for (final chunk in chunks) {
        emulator.consume(chunk);
      }

      final body = emulator.state.notification?['ncs_notification']
          as Map<String, dynamic>?;
      expect((body?['message'] as String?)?.length, 600);
    });
  });

  group('Bitmap', () {
    test('the address bytes are not mistaken for image data', () {
      final emulator = LensEmulator()
        ..consume([0x15, 0x00, 0x00, 0x1C, 0x00, 0x00, 0xAA, 0xBB])
        ..consume([0x15, 0x01, 0xCC])
        ..consume([0x20])
        ..consume([0x16, 0x00, 0x00, 0x00, 0x00]);

      expect(emulator.state.surface, LensSurface.image);
      expect(emulator.state.image, Uint8List.fromList([0xAA, 0xBB, 0xCC]));
      expect(emulator.state.imageComplete, isTrue);
    });
  });

  group('Settings', () {
    test('brightness and silent mode follow the packets', () {
      final emulator = LensEmulator()
        ..consume([0x01, 0x20, 0x01])
        ..consume([0x03, 0x0C]);

      expect(emulator.state.brightness, 0x20);
      expect(emulator.state.autoBrightness, isTrue);
      expect(emulator.state.silent, isTrue);

      emulator.consume([0x03, 0x0A]);
      expect(emulator.state.silent, isFalse);
    });

    test('the dashboard layout command is read as mode and panel', () {
      final packet = <int>[
        ...DashboardLayout.DASHBOARD_CHANGE_COMMAND,
        ...DashboardLayout.DASHBOARD_DUAL,
      ];
      final emulator = LensEmulator()..consume(packet);

      expect(emulator.state.dashboardMode, 0x01);
      expect(emulator.state.dashboardPanel, 0x00);
    });

    test('clearing the screen leaves the settings alone', () {
      final emulator = LensEmulator()
        ..consume([0x01, 0x20, 0x00])
        ..consume(TextMessage('a effacer').constructSendText().first)
        ..consume([0x18]);

      expect(emulator.state.surface, LensSurface.blank);
      expect(emulator.state.text, isEmpty);
      expect(emulator.state.brightness, 0x20);
    });
  });

  group('What it does not understand', () {
    test('an unknown opcode is remembered, not guessed at', () {
      final emulator = LensEmulator()..consume([0x4C]);

      expect(emulator.state.unhandled, contains(0x4C));
      expect(emulator.state.surface, LensSurface.blank);
    });
  });

  group('Framebuffer', () {
    test("the text column is the firmware's 488 pixels, centred", () {
      expect(LensFramebuffer.textLeft, 44);
      expect(LensFramebuffer.textLeft + LensFramebuffer.textWidth, 532);
    });

    test('a filled row is seen, and its position is known', () {
      final frame = LensFramebuffer()..fillRect(0, 10, 576, 1);

      expect(frame.lit, 576);
      expect(frame.lastLitRow, 10);
      expect(frame.spillsOutsideTextColumn, isTrue);
    });

    test('drawing inside the text column does not count as spill', () {
      final frame = LensFramebuffer()
        ..fillRect(LensFramebuffer.textLeft, 0, LensFramebuffer.textWidth, 4);

      expect(frame.spillsOutsideTextColumn, isFalse);
    });

    test('a rasterised buffer comes back as one bit per pixel', () {
      final rgba = Uint8List(
        LensFramebuffer.width * LensFramebuffer.height * 4,
      );
      // One lit pixel at the origin, everything else dark.
      rgba[1] = 0xFF;

      final frame = LensFramebuffer.fromRgba(rgba);
      expect(frame.get(0, 0), isTrue);
      expect(frame.lit, 1);
    });
  });
}
