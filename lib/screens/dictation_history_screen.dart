import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:g1_extended/services/dictation_service.dart';

/// Everything the glasses have heard and transcribed, newest first.
class DictationHistoryScreen extends StatefulWidget {
  const DictationHistoryScreen({super.key});

  @override
  State<DictationHistoryScreen> createState() => _DictationHistoryScreenState();
}

class _DictationHistoryScreenState extends State<DictationHistoryScreen> {
  late Future<List<Dictation>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = DictationService.singleton.history();
  }

  void _reload() {
    setState(() => _entries = DictationService.singleton.history());
  }

  Future<void> _clear() async {
    await DictationService.singleton.clearHistory();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear history',
            onPressed: _clear,
          ),
        ],
      ),
      body: FutureBuilder<List<Dictation>>(
        future: _entries,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing yet.\n\nHold a temple touchpad and speak, or say '
                  'your wake word.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: Icon(
                  entry.source == DictationSource.glasses
                      ? Icons.visibility_outlined
                      : Icons.smartphone_outlined,
                ),
                title: Text(entry.text),
                subtitle: Text(
                  DateFormat('d MMM, HH:mm').format(entry.capturedAt),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
