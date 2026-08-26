import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:g1_extended/services/voice_recordings.dart';

/// Everything the glasses have actually heard, as audio.
///
/// The dictation screen shows what was recognised; this one shows what was
/// said. They are not the same thing, and when they disagree this screen is
/// the one that is right.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _playerReady = false;

  late Future<List<Recording>> _recordings;
  StreamSubscription<void>? _watch;

  /// Which recording is playing, so only one tile shows a stop button.
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _recordings = VoiceRecordings.singleton.all();
    _watch = VoiceRecordings.singleton.changes.listen((_) => _reload());
    _openPlayer();
  }

  @override
  void dispose() {
    _watch?.cancel();
    if (_playerReady) _player.closePlayer();
    super.dispose();
  }

  Future<void> _openPlayer() async {
    try {
      await _player.openPlayer();
      if (mounted) setState(() => _playerReady = true);
    } catch (e) {
      debugPrint('RecordingsScreen: could not open the player: $e');
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _recordings = VoiceRecordings.singleton.all());
  }

  Future<void> _toggle(Recording recording) async {
    if (!_playerReady) return;

    if (_playingId == recording.id) {
      await _player.stopPlayer();
      if (mounted) setState(() => _playingId = null);
      return;
    }

    if (_player.isPlaying) await _player.stopPlayer();

    final file = await VoiceRecordings.singleton.fileFor(recording);
    if (!await file.exists()) {
      // The index thought it was there and it is not. Say so plainly
      // rather than showing a play button that does nothing.
      _say('That file is missing from the phone.');
      return;
    }

    try {
      await _player.startPlayer(
        fromURI: file.path,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          if (mounted) setState(() => _playingId = null);
        },
      );
      if (mounted) setState(() => _playingId = recording.id);
    } catch (e) {
      debugPrint('RecordingsScreen: playback failed: $e');
      _say('Could not play that recording.');
    }
  }

  /// Hands the audio file to the system share sheet.
  ///
  /// This is the way a recording leaves the phone for good — a backup, a
  /// message, a transcription service the wearer chose. No network of our
  /// own is involved; it goes wherever they send it.
  Future<void> _share(Recording recording) async {
    final file = await VoiceRecordings.singleton.fileFor(recording);
    if (!await file.exists()) {
      _say('That file is missing from the phone.');
      return;
    }

    final stamp = DateFormat('yyyy-MM-dd HH:mm').format(recording.capturedAt);
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'G1 recording $stamp',
        text: recording.hasTranscript ? recording.transcript : null,
      );
    } catch (e) {
      debugPrint('RecordingsScreen: could not share: $e');
      _say('Could not share that recording.');
    }
  }

  Future<void> _confirmDelete(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: const Text(
          'The audio is removed from the phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (_playingId == recording.id) {
      await _player.stopPlayer();
      if (mounted) setState(() => _playingId = null);
    }
    await VoiceRecordings.singleton.remove(recording.id);
  }

  Future<void> _recover() async {
    final found = await VoiceRecordings.singleton.recoverOrphans();
    _say(found == 0
        ? 'Nothing unlisted on disk.'
        : 'Put $found recording${found == 1 ? '' : 's'} back in the list.');
    _reload();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_page_outlined),
            tooltip: 'Look for unlisted audio on disk',
            onPressed: _recover,
          ),
        ],
      ),
      body: FutureBuilder<List<Recording>>(
        future: _recordings,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final recordings = snapshot.data!;
          if (recordings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing recorded yet.\n\nHold the right temple and speak. '
                  'The audio is kept here whether or not it can be '
                  'transcribed.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: recordings.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == recordings.length) return _footer(recordings);
              return _tile(recordings[index]);
            },
          );
        },
      ),
    );
  }

  Widget _tile(Recording recording) {
    final playing = _playingId == recording.id;
    final theme = Theme.of(context);

    return ListTile(
      leading: IconButton(
        icon: Icon(
          playing
              ? Icons.stop_circle_outlined
              : recording.isPlayable
                  ? Icons.play_circle_outline
                  : Icons.error_outline,
        ),
        tooltip: recording.isPlayable ? 'Play' : 'Not playable',
        onPressed: recording.isPlayable ? () => _toggle(recording) : null,
      ),
      title: Text(
        recording.hasTranscript ? recording.transcript : '(no transcript)',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: recording.hasTranscript
            ? null
            : theme.textTheme.bodyMedium
                ?.copyWith(fontStyle: FontStyle.italic),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('d MMM, HH:mm').format(recording.capturedAt)}'
            ' · ${_length(recording)}'
            ' · ${_where(recording.source)}',
          ),
          if (recording.transcriptError != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                recording.transcriptError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      isThreeLine: recording.transcriptError != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export the audio file',
            onPressed: () => _share(recording),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(recording),
          ),
        ],
      ),
    );
  }

  Widget _footer(List<Recording> recordings) {
    final bytes = recordings.fold<int>(0, (sum, r) => sum + r.byteLength);
    final megabytes = bytes / (1024 * 1024);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Text(
        '${recordings.length} recording${recordings.length == 1 ? '' : 's'}'
        ' · ${megabytes.toStringAsFixed(1)} MB on this phone',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String _length(Recording recording) {
    if (recording.duration == Duration.zero) return 'length unknown';
    final seconds = recording.duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }

  String _where(RecordingSource source) => switch (source) {
        RecordingSource.glassesNote => 'glasses note',
        RecordingSource.glassesLive => 'glasses mic',
        RecordingSource.phone => 'phone mic',
      };
}
