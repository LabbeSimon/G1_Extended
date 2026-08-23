/// What goes into one of the glasses' four note slots.
class SlotContent {
  const SlotContent({
    required this.name,
    required this.text,
    this.fromUser = false,
  });

  final String name;
  final String text;

  /// True for something the wearer typed, which outranks anything generated.
  final bool fromUser;

  bool get isEmpty => name.isEmpty && text.isEmpty;
}

/// Decides which of the four hardware note slots holds what.
///
/// The glasses keep exactly four notes, and two parts of this app each used
/// to write all four as though they owned them. The dashboard rewrote slots
/// one upward every sixty seconds and deleted whatever was left over; the
/// quick notes replayed the wearer's own text on every reconnection. Both
/// were correct in isolation and together they destroyed each other's work
/// on a one minute cycle, which is why a note written by hand would vanish
/// after a while, or on coming back to the app, apparently at random.
///
/// The rule is that something typed by a person is never overwritten by
/// something generated. Everything else fills in around it.
class NoteSlots {
  const NoteSlots._();

  /// The firmware exposes slots 1 to 4.
  static const int count = 4;

  /// Works out the final contents of every slot.
  ///
  /// [userNotes] is keyed by the slot the wearer chose; empty entries are
  /// ignored and release their slot. [generated] fills what remains, in
  /// order, and is truncated rather than allowed to displace anything.
  ///
  /// [hint] is the line telling a newcomer how to dictate a note. It is
  /// shown only when the wearer has no notes of their own — once there is
  /// one, the instruction has been followed and it is just a slot spent
  /// telling someone something they know.
  ///
  /// Returns every slot from 1 to [count]. A null value means the slot
  /// should be cleared.
  static Map<int, SlotContent?> plan({
    Map<int, SlotContent> userNotes = const {},
    List<SlotContent> generated = const [],
    SlotContent? hint,
  }) {
    final result = <int, SlotContent?>{
      for (var slot = 1; slot <= count; slot++) slot: null,
    };

    for (final entry in userNotes.entries) {
      final slot = entry.key;
      if (slot < 1 || slot > count) continue;
      if (entry.value.isEmpty) continue;
      result[slot] = SlotContent(
        name: entry.value.name,
        text: entry.value.text,
        fromUser: true,
      );
    }

    final free = [
      for (var slot = 1; slot <= count; slot++)
        if (result[slot] == null) slot,
    ];

    var next = 0;
    for (final item in generated) {
      if (next >= free.length) break;
      if (item.isEmpty) continue;
      result[free[next++]] = item;
    }

    final hasOwnNotes = result.values.any((c) => c?.fromUser ?? false);
    if (hint != null && !hint.isEmpty && !hasOwnNotes && next < free.length) {
      result[free[next]] = hint;
    }

    return result;
  }
}
