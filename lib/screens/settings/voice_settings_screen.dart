import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g1_extended/services/vosk_model_manager.dart';
import 'package:g1_extended/services/voice_input_service.dart';
import 'package:g1_extended/services/wake_word_service.dart';

/// Voice settings: wake word, which microphone to dictate through, and the
/// offline speech model everything on this screen depends on.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final WakeWordService _wakeWord = WakeWordService.singleton;
  final VoiceInputService _voiceInput = VoiceInputService.singleton;
  final VoskModelManager _models = VoskModelManager.singleton;

  bool _loading = true;
  bool _wakeWordEnabled = false;
  double _sensitivity = 0.5;
  String _wakeWordValue = 'computer';
  bool _useGlassesMic = false;
  bool _modelInstalled = false;
  int _modelBytes = 0;
  double _downloadProgress = 0;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _models.downloadProgress.listen((value) {
      if (mounted) setState(() => _downloadProgress = value);
    });
  }

  Future<void> _load() async {
    await _wakeWord.initialize();
    await _voiceInput.initialize();

    final prefs = await SharedPreferences.getInstance();
    final installed = await _models.isModelInstalled();
    final size = installed ? await _wakeWord.getModelSize() : 0;

    if (!mounted) return;
    setState(() {
      _wakeWordEnabled = _wakeWord.isEnabled;
      _sensitivity = _wakeWord.sensitivity;
      _wakeWordValue = _wakeWord.wakeWord;
      _useGlassesMic = prefs.getBool('use_glasses_microphone') ?? false;
      _modelInstalled = installed;
      _modelBytes = size;
      _loading = false;
    });
  }

  Future<void> _setUseGlassesMic(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_glasses_microphone', value);
    if (mounted) setState(() => _useGlassesMic = value);
  }

  Future<void> _downloadModel() async {
    setState(() => _downloading = true);
    await _models.load();
    final installed = await _models.isModelInstalled();
    final size = installed ? await _wakeWord.getModelSize() : 0;
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _modelInstalled = installed;
      _modelBytes = size;
    });
  }

  Future<void> _deleteModel() async {
    await _wakeWord.setEnabled(false);
    await _wakeWord.deleteModel();
    if (!mounted) return;
    setState(() {
      _modelInstalled = false;
      _modelBytes = 0;
      _wakeWordEnabled = false;
    });
  }

  String get _modelSizeLabel {
    if (_modelBytes <= 0) return 'not installed';
    return '${(_modelBytes / (1024 * 1024)).toStringAsFixed(0)} MB on device';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Voice')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _header('Microphone'),
          RadioGroup<bool>(
            groupValue: _useGlassesMic,
            onChanged: (value) => _setUseGlassesMic(value ?? false),
            child: const Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  title: Text('Phone microphone'),
                  subtitle: Text(
                    'Uses the system recogniser. More accurate, nothing to '
                    'download.',
                  ),
                ),
                RadioListTile<bool>(
                  value: true,
                  title: Text('Glasses microphone'),
                  subtitle: Text('Hands free. Needs the offline model below.'),
                ),
              ],
            ),
          ),
          const Divider(),

          if (_models.suspectedBadModel) ...[
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('The speech model would not load'),
              subtitle: const Text(
                'It was left in a state that stopped the app from starting, '
                'so it is no longer loaded automatically. Remove it and '
                'download it again.',
              ),
              trailing: TextButton(
                onPressed: () async {
                  await _models.discardSuspectModel();
                  await _load();
                },
                child: const Text('Remove'),
              ),
            ),
            const Divider(),
          ],
          _header('Offline speech model'),
          ListTile(
            title: const Text('Vosk small English'),
            subtitle: Text(_modelSizeLabel),
            trailing: _downloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      strokeWidth: 2,
                    ),
                  )
                : _modelInstalled
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete model',
                        onPressed: _deleteModel,
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Download model',
                        onPressed: _downloadModel,
                      ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Downloaded once from alphacephei.com. After that, speech never '
              'leaves the device.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          _header('Wake word'),
          SwitchListTile(
            value: _wakeWordEnabled,
            onChanged: _modelInstalled
                ? (value) async {
                    await _wakeWord.setEnabled(value);
                    if (mounted) setState(() => _wakeWordEnabled = value);
                  }
                : null,
            title: const Text('Listen for a wake word'),
            subtitle: Text(
              _modelInstalled
                  ? 'Say "$_wakeWordValue" to start dictating.'
                  : 'Download the offline model first.',
            ),
          ),
          if (_wakeWordEnabled) ...[
            ListTile(
              title: const Text('Sensitivity'),
              subtitle: Slider(
                value: _sensitivity,
                onChanged: (value) => setState(() => _sensitivity = value),
                onChangeEnd: _wakeWord.setSensitivity,
              ),
              trailing: Text('${(_sensitivity * 100).round()}%'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
