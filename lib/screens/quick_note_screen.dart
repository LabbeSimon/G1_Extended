import 'dart:async';

import 'package:flutter/material.dart';

import 'package:g1_extended/models/note_entry.dart';
import 'package:g1_extended/services/notes_library.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// Every note the phone holds, and which four are on the glasses.
///
/// The glasses keep four notes. This used to be four editors, one per slot,
/// so keeping something written last week meant giving up a slot to it and
/// writing a fifth note meant destroying one. The library holds as many as
/// you like; the pin decides which four go across.
class QuickNoteScreen extends StatefulWidget {
  const QuickNoteScreen({super.key});

  @override
  State<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends State<QuickNoteScreen> {
  final NotesLibrary _library = NotesLibrary.singleton;

  List<NoteEntry> _notes = const [];
  bool _loading = true;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = _library.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await _library.all();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _togglePin(NoteEntry note) async {
    if (note.isPinned) {
      await _library.unpin(note.id);
      return;
    }

    final result = await _library.pin(note.id);
    if (result.succeeded || !mounted) return;

    // Refused rather than resolved by evicting something. Naming what is in
    // the way lets the wearer choose; picking for them is how notes came to
    // disappear in the first place.
    final pinned = _notes.where((n) => n.isPinned).map((n) => n.displayTitle);
    _say('The glasses hold four notes and all four are taken: '
        '${pinned.join(', ')}. Unpin one to make room.');
  }

  Future<void> _open(NoteEntry? note) async {
    final entry = note ?? await _library.create();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _NoteEditor(id: entry.id),
    ));
    await _load();
  }

  Future<void> _delete(NoteEntry note) async {
    await _library.remove(note.id);
    if (mounted) _say('Deleted "${note.displayTitle}"');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pinnedCount = _notes.where((n) => n.isPinned).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(null),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const _Empty()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        '$pinnedCount of ${NotesLibrary.slotCount} slots on '
                        'the glasses. Everything else stays on the phone.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    for (final note in _notes)
                      Dismissible(
                        key: ValueKey(note.id),
                        direction: DismissDirection.endToStart,
                        background: const ColoredBox(
                          color: Colors.transparent,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 24),
                              child: Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                        onDismissed: (_) => _delete(note),
                        child: ListTile(
                          leading: PixelArt(
                            rows: note.isPinned
                                ? PixelArtwork.check
                                : PixelArtwork.note,
                            size: 20,
                          ),
                          title: Text(note.displayTitle),
                          subtitle: Text(
                            note.isPinned
                                ? 'Slot ${note.pinnedSlot} on the glasses'
                                : _preview(note),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: note.isPinned
                                ? 'Take off the glasses'
                                : 'Put on the glasses',
                            icon: Icon(note.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined),
                            onPressed: () => _togglePin(note),
                          ),
                          onTap: () => _open(note),
                        ),
                      ),
                  ],
                ),
    );
  }

  static String _preview(NoteEntry note) {
    final body = note.body.trim().replaceAll('\n', ' · ');
    return body.isEmpty ? 'On the phone only' : body;
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelArt(rows: PixelArtwork.note, size: 48),
              SizedBox(height: 16),
              Text(
                'No notes yet.\n\nWrite one here, or hold the right temple to '
                'dictate one. Pin up to four and they appear on the glasses.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

/// Editing one note.
///
/// Saves as you type. Nothing used to be written until an explicit send, so
/// text typed and then left behind — by going back, or switching slot — was
/// discarded without a word.
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.id});

  final String id;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  final NotesLibrary _library = NotesLibrary.singleton;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  NoteEntry? _entry;
  Timer? _autosave;

  /// Long enough that typing a word does not touch the disk, short enough
  /// that leaving the screen almost never outruns it — and the flush on
  /// dispose covers the case where it does.
  static const Duration _autosaveAfter = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _load();
    _title.addListener(_schedule);
    _body.addListener(_schedule);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    unawaited(_flush());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entry = await _library.byId(widget.id);
    if (!mounted || entry == null) return;
    setState(() {
      _entry = entry;
      _title.text = entry.title;
      _body.text = entry.body;
    });
  }

  void _schedule() {
    if (_entry == null) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveAfter, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    final entry = _entry;
    if (entry == null) return;
    _autosave?.cancel();
    await _library.update(entry.copyWith(
      title: _title.text,
      body: _body.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.isPinned == true
            ? 'Note · slot ${entry!.pinnedSlot}'
            : 'Note'),
      ),
      body: entry == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    helperText: 'Shown as the note name on the glasses.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _body,
                  minLines: 6,
                  maxLines: 20,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saved as you type. Pinned notes reach the glasses at once.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }
}
