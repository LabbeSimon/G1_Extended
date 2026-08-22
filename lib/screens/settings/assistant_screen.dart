import 'package:flutter/material.dart';

import 'package:g1_extended/services/assistant_service.dart';
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
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
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
    _baseUrl.text = await _assistant.baseUrl();
    _model.text = await _assistant.model();
    _apiKey.text = await _assistant.apiKey() ?? '';
    _prompt.text = await _assistant.prompt();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _assistant.setBaseUrl(_baseUrl.text);
    await _assistant.setModel(_model.text);
    await _assistant.setApiKey(_apiKey.text);
    await _assistant.setPrompt(_prompt.text);
  }

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
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'llama3.2, qwen2.5, gpt-4o-mini…',
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
                labelText: 'API key (optional)',
                helperText: 'Leave empty for a model you host yourself. '
                    'Stored in the Android keystore.',
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'This is not the assistant that was removed from this project. '
              'There is no account, no bundled provider and no default host: '
              'the app has no idea where your questions go until you type an '
              'address above. Point it at a machine you own and nothing '
              'leaves your network.\n\n'
              'The audio never travels. Speech is turned into text on the '
              'phone by the offline model, and only that text is sent.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
