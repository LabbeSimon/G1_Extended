import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'package:g1_extended/models/extension_manifest.dart';
import 'package:g1_extended/services/custom_cards_service.dart';

/// One entry of the public catalogue.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.manifestUrl,
  });

  final String id;
  final String name;
  final String author;
  final String description;
  final String version;
  final String manifestUrl;
}

/// The free extension catalogue: fetch, install, uninstall.
///
/// No backend anywhere. The catalogue is a static JSON file in a public git
/// repository; submitting an extension is a pull request, and moderation is
/// the merge button. There are no accounts, no payments — the format has no
/// price field to put a price in — and the catalogue is only ever fetched
/// when the user asks, never in the background.
///
/// Installing writes the extension's cards into the same store the user's
/// own cards live in, under a namespaced id. One rendering engine, one
/// screen where every card is visible, and uninstalling is deleting by
/// prefix. An installed card is the user's: they can toggle or edit it, and
/// reinstalling the extension resets it.
class ExtensionsService {
  ExtensionsService._internal();
  static final ExtensionsService singleton = ExtensionsService._internal();
  factory ExtensionsService() => singleton;

  static const String catalogUrl =
      'https://raw.githubusercontent.com/LabbeSimon/g1-extensions/main/catalog.json';

  /// A catalogue or manifest bigger than this is not what it claims to be.
  static const int maxDocumentBytes = 256 * 1024;

  static const String _boxName = 'extensions';
  static const String _cardIdPrefix = 'ext:';

  Future<Box> _openBox() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  // ------------------------------------------------------------- catalogue

  /// Fetches the catalogue. Explicitly, on the user's tap — never polled.
  Future<List<CatalogEntry>> fetchCatalog() async {
    final body = await _fetchDocument(Uri.parse(catalogUrl));
    if (body == null) return const [];

    try {
      final json = jsonDecode(body);
      final list = json is Map ? json['extensions'] : null;
      if (list is! List) return const [];

      return [
        for (final raw in list)
          if (raw is Map) ...[
            if (_entry(Map<String, dynamic>.from(raw)) != null)
              _entry(Map<String, dynamic>.from(raw))!,
          ],
      ];
    } catch (e) {
      debugPrint('ExtensionsService: unreadable catalogue: $e');
      return const [];
    }
  }

  CatalogEntry? _entry(Map<String, dynamic> raw) {
    final id = raw['id'] as String?;
    final name = raw['name'] as String?;
    final url = raw['manifestUrl'] as String?;
    if (id == null || name == null || url == null) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https')) return null;

    return CatalogEntry(
      id: id,
      name: name,
      author: raw['author'] as String? ?? '',
      description: raw['description'] as String? ?? '',
      version: raw['version'] as String? ?? '',
      manifestUrl: url,
    );
  }

  // ---------------------------------------------------------- installation

  /// Downloads, validates and installs. Throws [ManifestRejected] with the
  /// reason when the manifest is not acceptable.
  Future<ExtensionManifest> install(CatalogEntry entry) async {
    final body = await _fetchDocument(Uri.parse(entry.manifestUrl));
    if (body == null) {
      throw const ManifestRejected('the manifest could not be fetched');
    }

    final ExtensionManifest manifest;
    try {
      manifest = ExtensionManifestParser.parse(
        Map<String, dynamic>.from(jsonDecode(body) as Map),
      );
    } on ManifestRejected {
      rethrow;
    } catch (e) {
      throw ManifestRejected('the manifest is not valid JSON: $e');
    }

    if (manifest.id != entry.id) {
      // A manifest claiming a different identity than the catalogue row
      // that led to it is exactly the mismatch not to shrug at.
      throw ManifestRejected(
          'the manifest says "${manifest.id}" but the catalogue said '
          '"${entry.id}"');
    }

    // Replace any previous version wholesale.
    await uninstall(manifest.id);

    final cards = CustomCardsService.singleton;
    for (var i = 0; i < manifest.cards.length; i++) {
      final card = manifest.cards[i];
      await cards.save(CustomCard(
        id: '$_cardIdPrefix${manifest.id}:$i',
        title: card.title,
        template: card.template,
        sourceUrl: card.sourceUrl,
        sourcePath: card.sourcePath,
        refreshMinutes: card.refreshMinutes,
      ));
    }

    final box = await _openBox();
    await box.put(manifest.id, {
      'id': manifest.id,
      'name': manifest.name,
      'author': manifest.author,
      'description': manifest.description,
      'version': manifest.version,
      'cardCount': manifest.cards.length,
      'installedAt': DateTime.now().toIso8601String(),
    });

    return manifest;
  }

  Future<void> uninstall(String extensionId) async {
    final cards = CustomCardsService.singleton;
    for (final card in await cards.all()) {
      if (card.id.startsWith('$_cardIdPrefix$extensionId:')) {
        await cards.delete(card.id);
      }
    }
    final box = await _openBox();
    await box.delete(extensionId);
  }

  /// The installed extensions, as stored records.
  Future<List<Map<String, dynamic>>> installed() async {
    final box = await _openBox();
    return [
      for (final value in box.values)
        if (value is Map) Map<String, dynamic>.from(value),
    ];
  }

  Future<bool> isInstalled(String extensionId) async {
    final box = await _openBox();
    return box.containsKey(extensionId);
  }

  // -------------------------------------------------------------- plumbing

  Future<String?> _fetchDocument(Uri uri) async {
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('ExtensionsService: ${uri.host} answered '
            '${response.statusCode}');
        return null;
      }
      if (response.bodyBytes.length > maxDocumentBytes) {
        debugPrint('ExtensionsService: document too large, refusing');
        return null;
      }
      return utf8.decode(response.bodyBytes);
    } catch (e) {
      debugPrint('ExtensionsService: fetch failed: $e');
      return null;
    }
  }
}
