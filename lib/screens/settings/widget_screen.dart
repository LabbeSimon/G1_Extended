import 'package:flutter/material.dart';

import 'package:g1_extended/services/widget_panel.dart';

/// What the home screen widget shows, chosen here rather than hardcoded.
class WidgetScreen extends StatefulWidget {
  const WidgetScreen({super.key});

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  WidgetOptions _options = const WidgetOptions();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final options = await WidgetPanel.readOptions();
    if (!mounted) return;
    setState(() {
      _options = options;
      _loading = false;
    });
  }

  /// Every change lands on the widget immediately — a settings switch whose
  /// effect appears only at the next battery packet reads as broken.
  Future<void> _apply(WidgetOptions next) async {
    setState(() => _options = next);
    await WidgetPanel.saveOptions(next);
    await WidgetPanel.update();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Home screen widget')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            value: _options.showCase,
            title: const Text('Case battery'),
            subtitle: const Text(
              'Show the case level beside the glasses\', when it is known.',
            ),
            onChanged: (value) => _apply(WidgetOptions(
              showCase: value,
              alwaysBothSides: _options.alwaysBothSides,
              button: _options.button,
            )),
          ),
          SwitchListTile(
            value: _options.alwaysBothSides,
            title: const Text('Always both temples'),
            subtitle: const Text(
              'L and R at all times. Off, the widget shows one number — the '
              'emptier side — and splits only when the two drift apart.',
            ),
            onChanged: (value) => _apply(WidgetOptions(
              showCase: _options.showCase,
              alwaysBothSides: value,
              button: _options.button,
            )),
          ),
          const Divider(),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'THE BUTTON',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          RadioGroup<WidgetButtonRole>(
            groupValue: _options.button,
            onChanged: (role) {
              if (role == null) return;
              _apply(WidgetOptions(
                showCase: _options.showCase,
                alwaysBothSides: _options.alwaysBothSides,
                button: role,
              ));
            },
            child: const Column(
              children: [
                RadioListTile<WidgetButtonRole>(
                  value: WidgetButtonRole.adaptive,
                  title: Text('Follows the state'),
                  subtitle: Text('Speed toggle while connected, reconnect '
                      'while not.'),
                ),
                RadioListTile<WidgetButtonRole>(
                  value: WidgetButtonRole.reconnectOnly,
                  title: Text('Reconnect only'),
                  subtitle: Text('Appears when the glasses drop, gone '
                      'otherwise.'),
                ),
                RadioListTile<WidgetButtonRole>(
                  value: WidgetButtonRole.none,
                  title: Text('No button'),
                  subtitle: Text('The whole tile just opens the app.'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              'The widget is added from the launcher: long-press the home '
              'screen, Widgets, G1 Extended.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
