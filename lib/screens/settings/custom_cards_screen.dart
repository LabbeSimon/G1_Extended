import 'package:flutter/material.dart';

import 'package:g1_extended/services/card_template.dart';
import 'package:g1_extended/services/custom_cards_service.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Lines the wearer writes themselves, shown on the glasses.
class CustomCardsScreen extends StatefulWidget {
  const CustomCardsScreen({super.key});

  @override
  State<CustomCardsScreen> createState() => _CustomCardsScreenState();
}

class _CustomCardsScreenState extends State<CustomCardsScreen> {
  final CustomCardsService _cards = CustomCardsService.singleton;

  List<CustomCard> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _cards.all();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  Future<void> _edit(CustomCard card) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CardEditorScreen(card: card)),
    );
    if (saved ?? false) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _all.where((c) => c.enabled).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New card',
            onPressed: () => _edit(CustomCardsService.blank()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Write what you want the glasses to show. The hardware '
                    'holds four notes in total, shared with your agenda and '
                    'checklists, so the first ${CustomCardsService.maxCards} '
                    'enabled cards are the ones that make it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (active > CustomCardsService.maxCards)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'More cards are enabled than the glasses can show.',
                      style: TextStyle(fontSize: 12, color: AppColors.ink),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No cards yet.\n\nTap + to write one.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  for (final card in _all)
                    ListTile(
                      title: Text(card.title),
                      subtitle: Text(
                        card.template,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.technicalFont,
                          fontSize: 12,
                        ),
                      ),
                      leading: Icon(
                        card.hasSource ? Icons.cloud_outlined : Icons.notes,
                        color:
                            card.enabled ? AppColors.ink : AppColors.inkFaint,
                      ),
                      trailing: Switch(
                        value: card.enabled,
                        onChanged: (value) async {
                          await _cards.save(card.copyWith(enabled: value));
                          await _load();
                        },
                      ),
                      onTap: () => _edit(card),
                    ),
              ],
            ),
    );
  }
}

/// Writes one card, with the result shown as it is typed.
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({super.key, required this.card});

  final CustomCard card;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final CustomCardsService _cards = CustomCardsService.singleton;

  late final TextEditingController _title;
  late final TextEditingController _template;
  late final TextEditingController _url;
  late final TextEditingController _path;

  late int _refresh;
  String _preview = '';
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.card.title);
    _template = TextEditingController(text: widget.card.template);
    _url = TextEditingController(text: widget.card.sourceUrl ?? '');
    _path = TextEditingController(text: widget.card.sourcePath ?? '');
    _refresh = widget.card.refreshMinutes;

    _template.addListener(_refreshPreview);
    _refreshPreview();
  }

  @override
  void dispose() {
    _title.dispose();
    _template.dispose();
    _url.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _refreshPreview() async {
    final rendered = await _cards.preview(_current());
    if (mounted) setState(() => _preview = rendered);
  }

  CustomCard _current() => widget.card.copyWith(
        title: _title.text,
        template: _template.text,
        sourceUrl: _url.text,
        sourcePath: _path.text,
        refreshMinutes: _refresh,
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final value = await _cards.fetch(_current());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = value ?? 'Nothing came back. Check the URL and the path.';
    });
  }

  Future<void> _save() async {
    await _cards.save(_current());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    await _cards.delete(widget.card.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final unknown = CardTemplate.unknownTokens(_template.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Card'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _delete,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _template,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Line',
              helperText: 'Use {time}, {battery}, {temp}…',
              border: OutlineInputBorder(),
            ),
          ),

          if (unknown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nothing will fill: ${unknown.map((t) => '{$t}').join(', ')}',
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ),

          const SizedBox(height: 20),
          Text('On the glasses',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tile,
              borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
            ),
            child: Text(
              _preview.isEmpty ? '—' : _preview,
              style: const TextStyle(
                fontFamily: AppTheme.technicalFont,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
          ),

          const SizedBox(height: 28),
          Text('Available values',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in CardTemplate.known.entries)
                ActionChip(
                  label: Text('{${entry.key}}',
                      style: const TextStyle(fontSize: 11)),
                  tooltip: entry.value,
                  onPressed: () {
                    final text = _template.text;
                    final selection = _template.selection;
                    final at = selection.isValid
                        ? selection.baseOffset
                        : text.length;
                    _template.text = text.replaceRange(
                        at, at, '{${entry.key}}');
                  },
                ),
            ],
          ),

          const Divider(height: 40),
          Text('Source (optional)',
              style: Theme.of(context).textTheme.bodySmall),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              'Fill {value} from a web address of your own. This is the only '
              'request the app makes on your behalf rather than its own, so '
              'it is https only, and never more often than you set below.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'https://…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _path,
            decoration: const InputDecoration(
              labelText: 'JSON path (optional)',
              helperText: 'For example main.temp, or list.0.name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Every'),
              Expanded(
                child: Slider(
                  value: _refresh.toDouble(),
                  min: 1,
                  max: 120,
                  divisions: 119,
                  onChanged: (v) => setState(() => _refresh = v.round()),
                ),
              ),
              Text('$_refresh min'),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('Test the source'),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _testResult!,
                style: const TextStyle(
                  fontFamily: AppTheme.technicalFont,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
