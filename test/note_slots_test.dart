import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/note_slots.dart';

/// The glasses hold exactly four notes. Two parts of the app each used to
/// write all four as though they owned them: the dashboard rewrote them every
/// sixty seconds and deleted the leftovers, while quick notes replayed the
/// wearer's own text on every reconnection. Both were right alone; together
/// they destroyed each other's work on a one minute cycle.
void main() {
  SlotContent user(String text) => SlotContent(name: 'Mine', text: text);
  SlotContent gen(String text) => SlotContent(name: 'Auto', text: text);

  group('What a person typed is never overwritten', () {
    test('a filled slot keeps its content whatever the dashboard has', () {
      final plan = NoteSlots.plan(
        userNotes: {2: user('door code 4417')},
        generated: [gen('a'), gen('b'), gen('c'), gen('d'), gen('e')],
      );

      expect(plan[2]!.text, 'door code 4417');
      expect(plan[2]!.fromUser, isTrue);
    });

    test('four pinned notes leave nothing for the dashboard', () {
      final plan = NoteSlots.plan(
        userNotes: {
          for (var slot = 1; slot <= 4; slot++) slot: user('note $slot')
        },
        generated: [gen('a'), gen('b')],
        hint: gen('hint'),
      );

      for (var slot = 1; slot <= 4; slot++) {
        expect(plan[slot]!.text, 'note $slot');
      }
    });

    test('the wearer keeps the slot they chose, not the first free one', () {
      final plan = NoteSlots.plan(
        userNotes: {4: user('mine')},
        generated: [gen('a')],
      );

      expect(plan[4]!.text, 'mine');
      expect(plan[1]!.text, 'a');
    });
  });

  group('The dashboard fills what is left', () {
    test('in order, into the free slots', () {
      final plan = NoteSlots.plan(
        userNotes: {2: user('mine')},
        generated: [gen('a'), gen('b'), gen('c')],
      );

      expect(plan[1]!.text, 'a');
      expect(plan[3]!.text, 'b');
      expect(plan[4]!.text, 'c');
    });

    test('and is truncated rather than displacing anything', () {
      final plan = NoteSlots.plan(
        userNotes: {1: user('mine')},
        generated: [for (var i = 0; i < 20; i++) gen('item $i')],
      );

      expect(plan[1]!.text, 'mine');
      expect(plan.values.whereType<SlotContent>().length, 4);
    });
  });

  group('The hint is the first thing dropped', () {
    test('it takes a slot only when one is spare', () {
      final plan = NoteSlots.plan(generated: [gen('a')], hint: gen('hint'));
      expect(plan[2]!.text, 'hint');
    });

    test('it is dropped before a generated item', () {
      final plan = NoteSlots.plan(
        generated: [gen('a'), gen('b'), gen('c'), gen('d')],
        hint: gen('hint'),
      );
      expect(plan.values.map((c) => c?.text), isNot(contains('hint')));
    });

    test('and before a note of the wearer\'s', () {
      final plan = NoteSlots.plan(
        userNotes: {
          for (var slot = 1; slot <= 4; slot++) slot: user('note $slot')
        },
        hint: gen('hint'),
      );
      expect(plan.values.map((c) => c?.text), isNot(contains('hint')));
    });

    test('it disappears as soon as there is one note of your own', () {
      // It explains how to dictate a note. Once one exists the instruction
      // has been followed, and repeating it costs a slot.
      final plan = NoteSlots.plan(
        userNotes: {1: user('door code')},
        hint: gen('hint'),
      );
      expect(plan.values.map((c) => c?.text), isNot(contains('hint')));
      expect(plan[1]!.text, 'door code');
    });

    test('but it stays for someone who has none yet', () {
      final plan = NoteSlots.plan(generated: [gen('a')], hint: gen('hint'));
      expect(plan.values.map((c) => c?.text), contains('hint'));
    });
  });

  group('Empty means clear', () {
    test('every slot is accounted for, even the empty ones', () {
      final plan = NoteSlots.plan();
      expect(plan.keys.toList()..sort(), [1, 2, 3, 4]);
      expect(plan.values.every((c) => c == null), isTrue);
    });

    test('a blank note releases its slot rather than holding it', () {
      final plan = NoteSlots.plan(
        userNotes: {1: const SlotContent(name: '', text: '')},
        generated: [gen('a')],
      );
      expect(plan[1]!.text, 'a');
    });

    test('a slot out of range is ignored, not crashed on', () {
      expect(
        () => NoteSlots.plan(userNotes: {9: user('x'), 0: user('y')}),
        returnsNormally,
      );
    });
  });
}
