import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// How a request to the assistant ended.
sealed class AssistantResult {
  const AssistantResult();
}

class AssistantAnswer extends AssistantResult {
  final String text;
  const AssistantAnswer(this.text);
}

class AssistantFailure extends AssistantResult {
  final String reason;
  const AssistantFailure(this.reason);
}

/// Where the assistant's questions go.
enum AssistantProvider {
  /// Claude, through the Anthropic API with a key the user pastes in.
  claude,

  /// Any OpenAI-compatible endpoint: Ollama, LM Studio, llama.cpp, or a
  /// commercial service, at an address the user types.
  openAiCompatible,
}

/// Sends a question to an assistant and brings back an answer short enough to
/// read on a lens.
///
/// Two providers, both the user's choice and both off until they turn one on.
/// Claude is offered first because it needs only a key, not a server to run;
/// but the app contacts nothing until a key is in the keystore, and the
/// OpenAI-compatible provider still lets the whole thing stay on a machine the
/// user owns, where no question ever leaves their network.
///
/// This is not the account-bound assistant that was carved out of the fork:
/// there is no sign-in and no bundled credential. Claude here means an API key
/// the user obtained and pasted, nothing more.
class AssistantService {
  AssistantService._internal();
  static final AssistantService singleton = AssistantService._internal();
  factory AssistantService() => singleton;

  static const _enabledKey = 'assistant_enabled';
  static const _providerKey = 'assistant_provider';
  static const _baseUrlKey = 'assistant_base_url';
  static const _modelKey = 'assistant_model';
  static const _promptKey = 'assistant_prompt';
  static const _apiKeyKey = 'assistant_api_key';

  /// Claude's endpoint and the version header it requires. The host is fixed
  /// here, not typed by the user: it is the one address this app adds to the
  /// three it already contacts, and it is documented in AI-POLICY.md.
  static const String anthropicEndpoint =
      'https://api.anthropic.com/v1/messages';
  static const String anthropicVersion = '2023-06-01';

  /// The Claude model used until the user picks another. Haiku because a lens
  /// answer is two short lines that must feel instant and is paid for by the
  /// token; a harder question is a one-word change to a stronger model.
  static const String defaultClaudeModel = 'claude-haiku-4-5';

  /// Room for the answer. [shorten] trims it to [maxAnswerLength] anyway; this
  /// only has to be large enough not to cut a sentence off mid-generation.
  static const int maxTokens = 512;

  /// Answers longer than this cannot be read on the glasses.
  static const int maxAnswerLength = 220;

  /// Local models on modest hardware are not fast.
  static const Duration timeout = Duration(seconds: 60);

  /// What the assistant is told before every question. The brevity matters
  /// more than it looks: a model that answers in paragraphs is unusable here.
  static const String defaultPrompt =
      'You are shown on a pair of smart glasses with room for about two short '
      'lines. Answer in one or two sentences, under 200 characters. No '
      'preamble, no markdown, no lists. If you cannot answer briefly, say so.';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<AssistantProvider> provider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_providerKey) == 'openai'
        ? AssistantProvider.openAiCompatible
        : AssistantProvider.claude;
  }

  Future<void> setProvider(AssistantProvider value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _providerKey,
      value == AssistantProvider.openAiCompatible ? 'openai' : 'claude',
    );
  }

  Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? '';
  }

  Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, value.trim());
  }

  Future<String> model() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelKey) ?? '';
  }

  Future<void> setModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, value.trim());
  }

  Future<String> prompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_promptKey) ?? defaultPrompt;
  }

  Future<void> setPrompt(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_promptKey, value);
  }

  Future<String?> apiKey() async {
    try {
      return await _secure.read(key: _apiKeyKey);
    } catch (e) {
      debugPrint('AssistantService: could not read the key: $e');
      return null;
    }
  }

  Future<void> setApiKey(String? value) async {
    try {
      if (value == null || value.trim().isEmpty) {
        await _secure.delete(key: _apiKeyKey);
      } else {
        await _secure.write(key: _apiKeyKey, value: value.trim());
      }
    } catch (e) {
      debugPrint('AssistantService: could not store the key: $e');
    }
  }

  /// The Claude model to use: whatever the user set, or [defaultClaudeModel].
  Future<String> claudeModel() async {
    final chosen = await model();
    return chosen.isEmpty ? defaultClaudeModel : chosen;
  }

  /// True when there is enough configuration to try.
  Future<bool> isConfigured() async {
    if (!await isEnabled()) return false;
    switch (await provider()) {
      case AssistantProvider.claude:
        final key = await apiKey();
        return key != null && key.isNotEmpty;
      case AssistantProvider.openAiCompatible:
        return endpointFor(await baseUrl()) != null &&
            (await model()).isNotEmpty;
    }
  }

  /// Turns whatever the user typed into the completions endpoint.
  ///
  /// People paste `http://192.168.1.20:11434`, or the same with `/v1`, or the
  /// full path. All three should work rather than failing on a trailing
  /// slash. Plain http is allowed here, unlike everywhere else in the app,
  /// because a self-hosted model on a home network has no certificate and
  /// refusing it would rule out the best reason to use this at all.
  @visibleForTesting
  static Uri? endpointFor(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'http://$text';
    }
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }

    if (text.endsWith('/chat/completions')) return Uri.tryParse(text);
    if (text.endsWith('/v1')) return Uri.tryParse('$text/chat/completions');
    return Uri.tryParse('$text/v1/chat/completions');
  }

  /// Pulls the reply out of an Anthropic Messages response: the text of the
  /// first text block in `content`.
  @visibleForTesting
  static String? claudeAnswerFrom(Map<String, dynamic> body) {
    final content = body['content'];
    if (content is! List) return null;
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        final text = shorten(block['text'] as String);
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  /// Pulls the reply out of a chat completions response.
  @visibleForTesting
  static String? answerFrom(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;

    final message = (choices.first as Map)['message'];
    if (message is! Map) return null;

    final content = message['content'];
    if (content is! String) return null;

    return shorten(content);
  }

  /// Collapses an answer into something a lens can hold.
  @visibleForTesting
  static String shorten(String answer) {
    final flat = answer
        .replaceAll(RegExp(r'^\s*[-*]\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[*_`#]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (flat.length <= maxAnswerLength) return flat;

    // Cut at a sentence if there is one nearby, rather than mid-word.
    final cut = flat.substring(0, maxAnswerLength);
    final lastStop = cut.lastIndexOf(RegExp(r'[.!?]'));
    if (lastStop > maxAnswerLength ~/ 2) return cut.substring(0, lastStop + 1);

    final lastSpace = cut.lastIndexOf(' ');
    return '${cut.substring(0, lastSpace > 0 ? lastSpace : cut.length)}…';
  }

  /// Asks the configured assistant a question.
  Future<AssistantResult> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return const AssistantFailure('Nothing was heard');

    return switch (await provider()) {
      AssistantProvider.claude => _askClaude(trimmed),
      AssistantProvider.openAiCompatible => _askOpenAi(trimmed),
    };
  }

  /// Asks Claude, through the Anthropic Messages API.
  Future<AssistantResult> _askClaude(String question) async {
    final key = await apiKey();
    if (key == null || key.isEmpty) {
      return const AssistantFailure('No Claude API key set');
    }

    try {
      final response = await http
          .post(
            Uri.parse(anthropicEndpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': anthropicVersion,
            },
            body: jsonEncode({
              'model': await claudeModel(),
              'max_tokens': maxTokens,
              'system': await prompt(),
              'messages': [
                {'role': 'user', 'content': question},
              ],
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return AssistantFailure('Claude returned ${response.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const AssistantFailure('Unexpected reply');
      }

      final answer = claudeAnswerFrom(decoded);
      if (answer == null || answer.isEmpty) {
        return const AssistantFailure('Empty answer');
      }
      return AssistantAnswer(answer);
    } on TimeoutException {
      return const AssistantFailure('Timed out');
    } catch (e) {
      debugPrint('AssistantService: Claude request failed: $e');
      return const AssistantFailure('Could not reach Claude');
    }
  }

  /// Asks an OpenAI-compatible endpoint.
  Future<AssistantResult> _askOpenAi(String trimmed) async {
    final endpoint = endpointFor(await baseUrl());
    if (endpoint == null) {
      return const AssistantFailure('No endpoint set');
    }

    final chosenModel = await model();
    if (chosenModel.isEmpty) {
      return const AssistantFailure('No model set');
    }

    final key = await apiKey();

    try {
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': chosenModel,
              'messages': [
                {'role': 'system', 'content': await prompt()},
                {'role': 'user', 'content': trimmed},
              ],
              'stream': false,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return AssistantFailure('Endpoint returned ${response.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const AssistantFailure('Unexpected reply');
      }

      final answer = answerFrom(decoded);
      if (answer == null || answer.isEmpty) {
        return const AssistantFailure('Empty answer');
      }
      return AssistantAnswer(answer);
    } on TimeoutException {
      return const AssistantFailure('Timed out');
    } catch (e) {
      debugPrint('AssistantService: request failed: $e');
      return AssistantFailure('Could not reach the endpoint');
    }
  }
}
