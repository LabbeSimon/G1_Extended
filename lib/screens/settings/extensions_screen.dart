import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:g1_extended/models/extension_manifest.dart';
import 'package:g1_extended/services/extensions_service.dart';
import 'package:g1_extended/widgets/pixel_art.dart';

/// The free extension catalogue.
///
/// Everything here is declarative cards — never code — and everything is
/// free: the format has no price field and the terms forbid selling. What
/// an extension will fetch is shown before the install button, because
/// consent without the list is not consent.
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final ExtensionsService _service = ExtensionsService.singleton;

  List<Map<String, dynamic>> _installed = const [];
  List<CatalogEntry>? _catalog;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    final installed = await _service.installed();
    if (mounted) setState(() => _installed = installed);
  }

  Future<void> _refreshCatalog() async {
    setState(() => _fetching = true);
    final catalog = await _service.fetchCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _fetching = false;
    });
  }

  Future<void> _offerInstall(CatalogEntry entry) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.name,
                style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('by ${entry.author} · v${entry.version}',
                style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(entry.description),
            const SizedBox(height: 16),
            const Text(
              'Extensions are cards, never code. This one\'s manifest will '
              'be checked against the format limits, and any web address it '
              'reads from will appear on its cards in "My cards" — where you '
              'can edit or disable each one.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(sheet).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(sheet).pop(true),
                  child: const Text('Install'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final manifest = await _service.install(entry);
      _say('Installed ${manifest.name} — its cards are in "My cards".');
    } on ManifestRejected catch (e) {
      _say('Refused: ${e.reason}');
    }
    await _loadInstalled();
  }

  Future<void> _uninstall(Map<String, dynamic> record) async {
    await _service.uninstall(record['id'] as String);
    _say('Removed ${record['name']}');
    await _loadInstalled();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final installedIds = {for (final r in _installed) r['id']};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            tooltip: 'Terms',
            icon: const Icon(Icons.description_outlined, size: 20),
            onPressed: () => launchUrl(
              Uri.parse(
                  'https://github.com/LabbeSimon/G1_Extended/blob/main/TERMS.md'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Cards made by others, free — selling anything here is against '
              'the terms. You are responsible for what you install. The '
              'catalogue is only fetched when you ask.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (_installed.isNotEmpty) ...[
            _header('Installed'),
            for (final record in _installed)
              ListTile(
                leading: PixelArt(rows: PixelArtwork.grid, size: 18),
                title: Text(record['name'] as String? ?? ''),
                subtitle: Text(
                  'by ${record['author']} · v${record['version']} · '
                  '${record['cardCount']} card(s)',
                ),
                trailing: IconButton(
                  tooltip: 'Uninstall',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _uninstall(record),
                ),
              ),
            const Divider(),
          ],
          _header('Catalogue'),
          if (catalog == null && !_fetching)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonal(
                onPressed: _refreshCatalog,
                child: const Text('Fetch the catalogue'),
              ),
            )
          else if (_fetching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (catalog!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nothing there yet — or no connection. Extensions are '
                'submitted as pull requests on the g1-extensions repository.',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            for (final entry in catalog)
              ListTile(
                leading: PixelArt(rows: PixelArtwork.download, size: 18),
                title: Text(entry.name),
                subtitle: Text(
                  [
                    if (entry.author.isNotEmpty) 'by ${entry.author}',
                    entry.description,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: installedIds.contains(entry.id)
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => _offerInstall(entry),
              ),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
