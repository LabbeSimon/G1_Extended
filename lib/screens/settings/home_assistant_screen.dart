import 'package:flutter/material.dart';

import 'package:g1_extended/services/home_assistant_service.dart';

/// Connects the glasses to a Home Assistant instance.
///
/// Two separate things live here, and the screen keeps them apart because
/// people want them separately: speaking to the house, and reading a few of
/// its values on the lens.
class HomeAssistantScreen extends StatefulWidget {
  const HomeAssistantScreen({super.key});

  @override
  State<HomeAssistantScreen> createState() => _HomeAssistantScreenState();
}

class _HomeAssistantScreenState extends State<HomeAssistantScreen> {
  final HomeAssistantService _ha = HomeAssistantService.singleton;

  final _baseUrl = TextEditingController();
  final _token = TextEditingController();

  bool _loading = true;
  bool _enabled = false;
  bool _testing = false;
  String? _testResult;
  bool _testPassed = false;

  List<String> _chosen = [];
  List<HaEntity>? _available;
  bool _loadingEntities = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _ha.isEnabled();
    _baseUrl.text = await _ha.baseUrl();
    _token.text = await _ha.token() ?? '';
    final chosen = await _ha.lensEntities();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _chosen = chosen;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _ha.setBaseUrl(_baseUrl.text);
    await _ha.setToken(_token.text);
    await _ha.setLensEntities(_chosen);
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final result = await _ha.ping();
    if (!mounted) return;

    setState(() {
      _testing = false;
      _testPassed = result is HaOk;
      _testResult = switch (result) {
        HaOk(:final text) => text,
        HaFailure(:final reason) => reason,
      };
    });
  }

  Future<void> _loadEntities() async {
    await _save();
    setState(() => _loadingEntities = true);

    final entities = await _ha.states();
    if (!mounted) return;

    setState(() {
      _available = entities;
      _loadingEntities = false;
    });

    if (entities.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing came back. Check the address and the token.'),
        ),
      );
    }
  }

  Future<void> _pick() async {
    if (_available == null) await _loadEntities();
    if (!mounted || _available == null || _available!.isEmpty) return;

    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EntityPicker(
        entities: _available!,
        selected: _chosen,
      ),
    );

    if (chosen == null) return;
    setState(() => _chosen = chosen);
    await _ha.setLensEntities(chosen);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: () async {
              await _save();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            value: _enabled,
            title: const Text('Connect to Home Assistant'),
            subtitle: const Text(
              'Speak to the house through the temple, and put a few of its '
              'values on the lens. Off by default, and nothing is contacted '
              'until you switch it on.',
            ),
            onChanged: (value) async {
              await _ha.setEnabled(value);
              if (mounted) setState(() => _enabled = value);
            },
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: 'http://192.168.1.20:8123',
                helperText: 'The base address, not a dashboard page. Plain '
                    'http works on your own network; https keeps the token '
                    'off the wire.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _token,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Long-lived access token',
                helperText: 'Home Assistant > your profile > Security > '
                    'Long-lived access tokens. Kept in the phone keystore.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _testing ? null : _test,
                  child: Text(_testing ? 'Trying…' : 'Test the connection'),
                ),
                const SizedBox(width: 12),
                if (_testResult != null)
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _testPassed
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 32),

          ListTile(
            title: const Text('On the lens'),
            subtitle: Text(
              _chosen.isEmpty
                  ? 'Nothing chosen. The lens holds four notes in total, '
                      'shared with your cards and checklists.'
                  : '${_chosen.length} of ${HomeAssistantService.maxLensEntities}',
            ),
            trailing: _loadingEntities
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Choose what to show',
                    onPressed: _pick,
                  ),
          ),

          for (final id in _chosen)
            ListTile(
              dense: true,
              leading: const Icon(Icons.circle, size: 10),
              title: Text(id),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: () async {
                  final next = [..._chosen]..remove(id);
                  setState(() => _chosen = next);
                  await _ha.setLensEntities(next);
                },
              ),
            ),

          const Divider(height: 32),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Text(
              'Hold a temple and say what you want — "turn off the hall '
              'light", "allume la cuisine". The whole sentence goes to Home '
              'Assistant, which does its own intent matching in your own '
              'language, and its reply appears on the lens.\n\n'
              'When no house is connected, those phrases are treated as '
              'ordinary questions instead.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks up to [HomeAssistantService.maxLensEntities] entities.
///
/// Searchable because a real Home Assistant has hundreds of entities and
/// scrolling to find one is not a thing anybody should do on a phone.
class _EntityPicker extends StatefulWidget {
  final List<HaEntity> entities;
  final List<String> selected;

  const _EntityPicker({required this.entities, required this.selected});

  @override
  State<_EntityPicker> createState() => _EntityPickerState();
}

class _EntityPickerState extends State<_EntityPicker> {
  late final List<String> _selected = [...widget.selected];
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final needle = _filter.toLowerCase();
    final shown = needle.isEmpty
        ? widget.entities
        : widget.entities
            .where((e) =>
                e.friendlyName.toLowerCase().contains(needle) ||
                e.entityId.toLowerCase().contains(needle))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final entity = shown[index];
                  final picked = _selected.contains(entity.entityId);
                  final full =
                      _selected.length >= HomeAssistantService.maxLensEntities;

                  return CheckboxListTile(
                    value: picked,
                    // A full lens disables the rest rather than silently
                    // dropping the fifth choice later.
                    onChanged: !picked && full
                        ? null
                        : (value) => setState(() {
                              if (value == true) {
                                _selected.add(entity.entityId);
                              } else {
                                _selected.remove(entity.entityId);
                              }
                            }),
                    title: Text(entity.friendlyName),
                    subtitle: Text('${entity.entityId} · ${entity.display}'),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
