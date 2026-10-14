import 'package:flutter/material.dart';

import 'package:g1_extended/screens/settings/home_assistant_screen.dart';
import 'package:g1_extended/screens/settings/voice_settings_screen.dart';
import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/dictation_service.dart';
import 'package:g1_extended/services/home_assistant_service.dart';
import 'package:g1_extended/services/vosk_model_manager.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Chooses who answers the glasses: Claude directly, or Home Assistant.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final AssistantService _assistant = AssistantService.singleton;
  final HomeAssistantService _house = HomeAssistantService.singleton;

  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _prompt = TextEditingController();

  bool _loading = true;
  bool _enabled = false;
  bool _hadCredentials = false;
  bool _glassesMic = true;
  bool _speechModelReady = true;
  AssistantProvider _provider = AssistantProvider.claude;
  String _haAgent = '';
  bool _houseReady = false;
  List<HaEntity> _agents = const [];
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSpeech();
    _loadHouse();
  }

  /// Whether a question can be understood at all: the glasses microphone
  /// records it and needs the offline model to turn it into text.
  Future<void> _loadSpeech() async {
    final glassesMic = await DictationService.usesGlassesMicrophone();
    final models = VoskModelManager.singleton;
    await models.loadSelection();
    final ready = !glassesMic || await models.isModelInstalled();
    if (!mounted) return;
    setState(() {
      _glassesMic = glassesMic;
      _speechModelReady = ready;
    });
  }

  /// Whether Home Assistant is connected, and which agents it offers: its
  /// own, plus any model added to it (Claude, Ollama…), each a
  /// `conversation.*` entity.
  Future<void> _loadHouse() async {
    final ready = await _house.isConfigured();
    final agents = ready ? await _house.conversationAgents() : <HaEntity>[];
    if (!mounted) return;
    setState(() {
      _houseReady = ready;
      _agents = agents;
    });
  }

  @override
  void dispose() {
    _model.dispose();
    _apiKey.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _assistant.isEnabled();
    final provider = await _assistant.provider();
    _model.text = await _assistant.model();
    _apiKey.text = await _assistant.apiKey() ?? '';
    _prompt.text = await _assistant.prompt();
    final haAgent = await _assistant.haAgent();
    final hadCredentials = await _assistant.hasCredentials();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hadCredentials = hadCredentials;
      _provider = provider;
      _haAgent = haAgent;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _assistant.setProvider(_provider);
    await _assistant.setModel(_model.text);
    await _assistant.setApiKey(_apiKey.text);
    await _assistant.setPrompt(_prompt.text);
    await _assistant.setHaAgent(_haAgent);

    // Pasting a key, or choosing a connected Home Assistant, is asking for
    // the assistant. Making people also find the switch above left every
    // question shown back as plain dictation. Only the first time: someone
    // who turned it off on purpose and then edits the prompt keeps it off.
    if (!_hadCredentials && await _assistant.hasCredentials()) {
      _hadCredentials = true;
      await _assistant.setEnabled(true);
      if (mounted) setState(() => _enabled = true);
    }
  }

  bool get _isClaude => _provider == AssistantProvider.claude;

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final result = await _assistant.ask('Reply with the single word: ready.');
    if (!mounted) return;

    setState(() {
      _testing = false;
      _testResult = switch (result) {
        AssistantAnswer(:final text) => text,
        AssistantFailure(:final reason) => reason,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final speech = _glassesMic
        ? 'Only the text of your question is sent, never the audio: it is '
            'recorded, then turned into text on the phone by the offline model.'
        : 'Only the text of your question is sent, never the audio. With the '
            'phone microphone, Android\'s own recogniser turns it into text, '
            'and it may use the network.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Hold the left temple, ask, then let go: the answer appears on '
              'the lens. The right temple dictates a note instead.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (!_speechModelReady)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download the speech model first'),
              subtitle: Text(
                'Your question is recorded, then turned into text on the '
                'phone by an offline model '
                '(${VoskModelManager.singleton.model.languageLabel}). A '
                'one-time download, in Voice.',
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceSettingsScreen()),
                );
                _loadSpeech();
              },
            ),
          SwitchListTile(
            value: _enabled,
            title: const Text('Ask an assistant'),
            subtitle: const Text(
              'Speech is recognised on the phone, the text goes to the '
              'assistant chosen below, and the answer appears on the lens.',
            ),
            onChanged: (value) async {
              await _assistant.setEnabled(value);
              if (mounted) setState(() => _enabled = value);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<AssistantProvider>(
              segments: const [
                ButtonSegment(
                  value: AssistantProvider.claude,
                  label: Text('Claude'),
                ),
                ButtonSegment(
                  value: AssistantProvider.homeAssistant,
                  label: Text('Home Assistant'),
                ),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.first),
            ),
          ),
          if (_isClaude) ..._claudeFields() else ..._houseFields(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Test it'),
            ),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _testResult!,
                style: const TextStyle(
                  fontFamily: AppTheme.technicalFont,
                  fontSize: 12,
                ),
              ),
            ),
          const Divider(height: 40),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              _isClaude
                  ? 'Claude runs on Anthropic\'s servers. Your question and '
                      'the system prompt are sent to api.anthropic.com with '
                      'the key you paste; nothing is sent until you add one, '
                      'and there is no account or sign-in — only your key.\n\n'
                      '$speech Choose Home Assistant to keep everything on a '
                      'machine you own.'
                  : 'Your question goes to your own Home Assistant, to the '
                      'agent chosen above, and to nothing else. What that '
                      'agent does with it — answer on its own, or ask a model '
                      'you added to Home Assistant — is set up over there.\n\n'
                      '$speech',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _claudeFields() => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: AssistantService.defaultClaudeModel,
              helperText: 'Empty uses ${AssistantService.defaultClaudeModel} '
                  '— fast and cheap. Try claude-opus-5 for harder questions.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Claude API key',
              helperText: 'From console.anthropic.com. Stored in the Android '
                  'keystore, sent only to api.anthropic.com.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: TextField(
            controller: _prompt,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'System prompt',
              helperText: 'The brevity instruction matters: a model that '
                  'answers in paragraphs is unreadable on glasses.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ];

  List<Widget> _houseFields() {
    if (!_houseReady) {
      return [
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: const Text('Connect Home Assistant first'),
          subtitle: const Text(
            'Its address and a long-lived token, in the Home Assistant '
            'settings. Every agent it offers then shows up here.',
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HomeAssistantScreen()),
            );
            _loadHouse();
          },
        ),
      ];
    }

    // The saved agent may be gone from Home Assistant since; the default
    // stands in rather than a dropdown with nothing selected.
    final known = _agents.any((a) => a.entityId == _haAgent);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: DropdownButtonFormField<String>(
          initialValue: known ? _haAgent : '',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Agent',
            helperText: 'Add Claude, Ollama or another model to Home '
                'Assistant and it appears in this list.',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Home Assistant\'s default'),
            ),
            for (final agent in _agents)
              DropdownMenuItem(
                value: agent.entityId,
                child: Text(agent.friendlyName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _haAgent = value ?? ''),
        ),
      ),
    ];
  }
}
