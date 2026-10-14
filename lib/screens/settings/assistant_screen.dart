import 'package:flutter/material.dart';

import 'package:g1_extended/screens/settings/voice_settings_screen.dart';
import 'package:g1_extended/services/assistant_service.dart';
import 'package:g1_extended/services/dictation_service.dart';
import 'package:g1_extended/services/vosk_model_manager.dart';
import 'package:g1_extended/theme/app_theme.dart';

/// Points the glasses at an assistant endpoint of the user's choosing.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final AssistantService _assistant = AssistantService.singleton;

  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _prompt = TextEditingController();

  bool _loading = true;
  bool _enabled = false;
  bool _hadCredentials = false;
  bool _glassesMic = true;
  bool _speechModelReady = true;
  AssistantProvider _provider = AssistantProvider.claude;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSpeech();
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

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _assistant.isEnabled();
    final provider = await _assistant.provider();
    _baseUrl.text = await _assistant.baseUrl();
    _model.text = await _assistant.model();
    _apiKey.text = await _assistant.apiKey() ?? '';
    _prompt.text = await _assistant.prompt();
    final hadCredentials = await _assistant.hasCredentials();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hadCredentials = hadCredentials;
      _provider = provider;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _assistant.setProvider(_provider);
    await _assistant.setBaseUrl(_baseUrl.text);
    await _assistant.setModel(_model.text);
    await _assistant.setApiKey(_apiKey.text);
    await _assistant.setPrompt(_prompt.text);

    // Pasting a key is asking for the assistant. Making people also find the
    // switch above left a key saved and every question shown back as plain
    // dictation. Only the first time: someone who turned it off on purpose
    // and then edits the prompt keeps it off.
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
              'Speech is recognised on the phone, the text is sent to the '
              'endpoint below, and the answer appears on the lens.',
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
                  value: AssistantProvider.openAiCompatible,
                  label: Text('Self-hosted'),
                ),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => setState(() => _provider = s.first),
            ),
          ),
          if (!_isClaude)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Endpoint',
                  hintText: 'http://192.168.1.20:11434',
                  helperText: 'Ollama, LM Studio, llama.cpp, or any '
                      'OpenAI-compatible service',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: _isClaude
                    ? AssistantService.defaultClaudeModel
                    : 'llama3.2, qwen2.5, gpt-4o-mini…',
                helperText: _isClaude
                    ? 'Empty uses ${AssistantService.defaultClaudeModel} — '
                        'fast and cheap. Try claude-opus-5 for harder questions.'
                    : null,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isClaude ? 'Claude API key' : 'API key (optional)',
                helperText: _isClaude
                    ? 'From console.anthropic.com. Stored in the Android '
                        'keystore, sent only to api.anthropic.com.'
                    : 'Leave empty for a model you host yourself. '
                        'Stored in the Android keystore.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
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
              label: const Text('Test the endpoint'),
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
                      '$speech Prefer self-hosted to keep everything on a '
                      'machine you own.'
                  : 'There is no account and no bundled credential: the app '
                      'has no idea where your questions go until you type an '
                      'address above. Point it at a machine you own and '
                      'nothing leaves your network.\n\n$speech',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
