/// One note in the library.
///
/// The glasses hold four; the phone holds as many as you like. Which four go
/// to the glasses is a property of the note — the slot it is pinned to —
/// rather than a separate list, so a note cannot be pinned and missing, or
/// present and unpinned, at the same time.
class NoteEntry {
  const NoteEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.pinnedSlot,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  /// 1 to 4 when this note occupies a slot on the glasses, null otherwise.
  final int? pinnedSlot;

  bool get isPinned => pinnedSlot != null;
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  /// What to call it when the wearer gave it no title.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return 'Untitled';
    return firstLine.length <= 28 ? firstLine : '${firstLine.substring(0, 27)}…';
  }

  NoteEntry copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    int? pinnedSlot,
    bool clearPin = false,
  }) =>
      NoteEntry(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
        pinnedSlot: clearPin ? null : (pinnedSlot ?? this.pinnedSlot),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'pinnedSlot': pinnedSlot,
      };

  static NoteEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    if (id == null || id.isEmpty) return null;

    final slot = raw['pinnedSlot'] as int?;
    return NoteEntry(
      id: id,
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        raw['updatedAt'] as int? ?? 0,
      ),
      // A slot outside the hardware's range is dropped rather than carried,
      // so a bad write cannot make a note permanently unpinnable.
      pinnedSlot: (slot != null && slot >= 1 && slot <= 4) ? slot : null,
    );
  }
}

/// Why a pin was refused.
enum PinRefusal {
  /// All four slots are taken. Naming them is better than evicting one.
  noFreeSlot,

  /// The requested slot already holds a different note.
  slotTaken,
}

class PinResult {
  const PinResult.ok()
      : refusal = null,
        occupiedBy = null;
  const PinResult.refused(this.refusal, {this.occupiedBy});

  final PinRefusal? refusal;

  /// The note already in the way, so the interface can name it.
  final NoteEntry? occupiedBy;

  bool get succeeded => refusal == null;
}
