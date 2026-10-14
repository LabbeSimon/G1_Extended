import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live translation of what someone is saying, entirely on the device.
///
/// The engine is ML Kit's on-device translator: each language is a model of
/// roughly thirty megabytes, downloaded once from Google and then owned —
/// after that no text ever leaves the phone, which is the only arrangement
/// this app would accept for something listening to a conversation. The
/// one-off download is the same bargain the Vosk speech models strike, and
/// it is disclosed the same way.
class TranslationService {
  TranslationService._internal();
  static final TranslationService singleton = TranslationService._internal();
  factory TranslationService() => singleton;

  static const String _fromKey = 'translate_from';
  static const String _toKey = 'translate_to';

  /// The pairs offered in the interface. ML Kit knows dozens; a picker of
  /// dozens is a chore. The stored value is the BCP-47 code, so widening
  /// this list later migrates nobody.
  static const Map<String, String> languages = {
    'en': 'English',
    'fr': 'Français',
    'es': 'Español',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'nl': 'Nederlands',
    'ja': '日本語',
    'zh': '中文',
  };

  OnDeviceTranslator? _translator;
  String? _activePair;

  Future<(String, String)> pair() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getString(_fromKey) ?? 'en',
      prefs.getString(_toKey) ?? 'fr',
    );
  }

  Future<void> setPair(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fromKey, from);
    await prefs.setString(_toKey, to);
  }

  static TranslateLanguage? _language(String code) =>
      TranslateLanguage.values
          .cast<TranslateLanguage?>()
          .firstWhere((l) => l!.bcpCode == code, orElse: () => null);

  /// Whether both models of the configured pair are on the device.
  Future<bool> modelsReady() async {
    final (from, to) = await pair();
    final manager = OnDeviceTranslatorModelManager();
    return await manager.isModelDownloaded(from) &&
        await manager.isModelDownloaded(to);
  }

  /// Downloads the configured pair's models. The interface calls this from
  /// an explicit button — thirty megabytes twice is nothing to do silently.
  Future<bool> downloadModels() async {
    final (from, to) = await pair();
    final manager = OnDeviceTranslatorModelManager();
    try {
      if (!await manager.isModelDownloaded(from)) {
        await manager.downloadModel(from);
      }
      if (!await manager.isModelDownloaded(to)) {
        await manager.downloadModel(to);
      }
      return true;
    } catch (e) {
      debugPrint('TranslationService: model download failed: $e');
      return false;
    }
  }

  /// Removes the configured pair's models from the device.
  Future<void> deleteModels() async {
    await _close();
    final (from, to) = await pair();
    final manager = OnDeviceTranslatorModelManager();
    try {
      await manager.deleteModel(from);
      await manager.deleteModel(to);
    } catch (e) {
      debugPrint('TranslationService: model delete failed: $e');
    }
  }

  /// Translates one finished segment. Returns null when it cannot — missing
  /// models, an unknown code — so the caller shows the original rather than
  /// nothing: a caption that vanishes in translation is worse than one left
  /// untranslated.
  Future<String?> translate(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final (from, to) = await pair();
    if (from == to) return trimmed;

    final source = _language(from);
    final target = _language(to);
    if (source == null || target == null) return null;

    final wanted = '$from>$to';
    if (_activePair != wanted) {
      await _close();
      _translator = OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      );
      _activePair = wanted;
    }

    try {
      return await _translator!.translateText(trimmed);
    } catch (e) {
      debugPrint('TranslationService: translate failed: $e');
      return null;
    }
  }

  Future<void> _close() async {
    await _translator?.close();
    _translator = null;
    _activePair = null;
  }
}
