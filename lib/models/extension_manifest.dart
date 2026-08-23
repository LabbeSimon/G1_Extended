/// An extension: cards someone else wrote, that you chose to install.
///
/// Deliberately not code. A manifest declares lines for the lens — the same
/// `{time}`, `{battery}`, `{value}`-from-a-URL templates the user's own
/// cards use — and nothing that executes. That line is what makes a free
/// community catalogue possible at all: declarative cards are harmless by
/// construction, while an app that downloads and runs third-party code is a
/// malware vector and a store-policy violation. Anyone who needs more than
/// the template language contributes Dart to the app itself, in a pull
/// request, in the open.
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.cards,
  });

  final String id;
  final String name;
  final String author;
  final String description;
  final String version;
  final List<ExtensionCard> cards;

  /// Every URL this extension will ever contact, for the install screen to
  /// show before the button. Informed consent needs the list, not a
  /// summary.
  List<String> get sourceUrls => [
        for (final card in cards)
          if (card.sourceUrl != null) card.sourceUrl!,
      ];
}

class ExtensionCard {
  const ExtensionCard({
    required this.title,
    required this.template,
    this.sourceUrl,
    this.sourcePath,
    this.refreshMinutes = 15,
  });

  final String title;
  final String template;
  final String? sourceUrl;
  final String? sourcePath;
  final int refreshMinutes;
}

/// Why a manifest was refused. One reason at a time, precise enough for the
/// author to fix.
class ManifestRejected implements Exception {
  const ManifestRejected(this.reason);
  final String reason;

  @override
  String toString() => 'ManifestRejected: $reason';
}

abstract final class ExtensionManifestParser {
  /// The limits are the security model, so they are named, not scattered.
  static const int maxCards = 4;
  static const int maxTitleLength = 40;
  static const int maxTemplateLength = 200;
  static const int maxDescriptionLength = 500;

  /// Third parties poll gently. The user's own cards may go to one minute;
  /// a catalogue extension may not.
  static const int minRefreshMinutes = 5;

  static final RegExp _idShape = RegExp(r'^[a-z0-9][a-z0-9\-]{1,63}$');

  /// Parses and validates, or throws [ManifestRejected] saying why.
  static ExtensionManifest parse(Map<String, dynamic> json) {
    if (json['formatVersion'] != 1) {
      throw const ManifestRejected(
          'formatVersion must be 1 — newer formats need a newer app');
    }

    final id = _requiredString(json, 'id');
    if (!_idShape.hasMatch(id)) {
      throw ManifestRejected(
          'id "$id" must be lowercase letters, digits and dashes');
    }

    final name = _requiredString(json, 'name');
    final author = _requiredString(json, 'author');
    final version = _requiredString(json, 'version');
    final description = json['description'] as String? ?? '';
    if (description.length > maxDescriptionLength) {
      throw const ManifestRejected('description is too long');
    }

    final rawCards = json['cards'];
    if (rawCards is! List || rawCards.isEmpty) {
      throw const ManifestRejected('an extension must declare cards');
    }
    if (rawCards.length > maxCards) {
      throw ManifestRejected('at most $maxCards cards — the lens has four '
          'note slots and other things want them too');
    }

    final cards = <ExtensionCard>[];
    for (final raw in rawCards) {
      if (raw is! Map) throw const ManifestRejected('malformed card entry');
      cards.add(_card(Map<String, dynamic>.from(raw)));
    }

    return ExtensionManifest(
      id: id,
      name: name,
      author: author,
      description: description,
      version: version,
      cards: cards,
    );
  }

  static ExtensionCard _card(Map<String, dynamic> json) {
    final title = _requiredString(json, 'title');
    if (title.length > maxTitleLength) {
      throw ManifestRejected('card title "$title" is too long');
    }

    final template = _requiredString(json, 'template');
    if (template.length > maxTemplateLength) {
      throw const ManifestRejected('a card template is too long');
    }

    final sourceUrl = (json['sourceUrl'] as String?)?.trim();
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      final uri = Uri.tryParse(sourceUrl);
      // https only, no exceptions. The user's own cards get the same rule;
      // a stranger's card certainly does not get a weaker one.
      if (uri == null || !uri.isScheme('https')) {
        throw ManifestRejected('sourceUrl must be https: $sourceUrl');
      }
    }

    final refresh = json['refreshMinutes'] as int? ?? 15;

    return ExtensionCard(
      title: title,
      template: template,
      sourceUrl: (sourceUrl?.isEmpty ?? true) ? null : sourceUrl,
      sourcePath: (json['sourcePath'] as String?)?.trim(),
      refreshMinutes:
          refresh < minRefreshMinutes ? minRefreshMinutes : refresh,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = (json[key] as String?)?.trim() ?? '';
    if (value.isEmpty) throw ManifestRejected('$key is required');
    return value;
  }
}
