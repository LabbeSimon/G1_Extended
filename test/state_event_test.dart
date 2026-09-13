import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/state_event.dart';
import 'package:g1_extended/services/glasses_event_log.dart';

void main() {
  group('Naming what the glasses report', () {
    test('the four sub-codes the app acts on keep their meaning', () {
      // These are the ones with behaviour attached in the receiver. If a
      // number here moves, a gesture stops working.
      expect(StateEvent.fromId(0x00), StateEvent.touchbarDoubleTap);
      expect(StateEvent.fromId(0x01), StateEvent.touchbarSingleTap);
      expect(StateEvent.fromId(23), StateEvent.touchbarHoldStart);
      expect(StateEvent.fromId(24), StateEvent.touchbarHoldEnd);
    });

    test('the case battery sub-code agrees with the parser that reads it', () {
      expect(StateEvent.fromId(0x0F), StateEvent.caseBattery);
    });

    test('an unnamed sub-code says so rather than being invented', () {
      expect(StateEvent.fromId(0x7B), isNull);
      expect(StateEvent.describe(0x7B), 'Unnamed 0x7B');
    });

    test('a named one reads with its number beside it', () {
      expect(StateEvent.describe(0x06), 'Glasses worn (0x06)');
    });

    test('no two events claim the same sub-code', () {
      final ids = StateEvent.values.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('The log', () {
    setUp(GlassesEventLog.instance.clear);

    test('keeps the most recent first', () {
      GlassesEventLog.instance.record('left', 0x06);
      GlassesEventLog.instance.record('right', 0x07);

      expect(GlassesEventLog.instance.events.first.subcommand, 0x07);
      expect(GlassesEventLog.instance.events.first.label,
          'Glasses removed (0x07)');
    });

    test('never grows past its depth', () {
      for (var i = 0; i < GlassesEventLog.depth + 20; i++) {
        GlassesEventLog.instance.record('left', i & 0xFF);
      }

      expect(GlassesEventLog.instance.events.length, GlassesEventLog.depth);
    });

    test('marks what nobody has named', () {
      GlassesEventLog.instance.record('left', 0x7B);

      expect(GlassesEventLog.instance.events.first.isUnnamed, isTrue);
    });
  });
}
