import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/widget_panel.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';

/// The home screen widget's provider is Kotlin and cannot share code with
/// the app, so its display rules are copies. These tests exist to make the
/// copies impossible to change apart by accident: break one of these and the
/// failure message names the file holding the twin.
void main() {
  test('the button roles speak the wire values the provider expects', () {
    // GlassesWidgetProvider.kt compares against these exact strings.
    expect(WidgetButtonRole.adaptive.wire, 'adaptive');
    expect(WidgetButtonRole.reconnectOnly.wire, 'reconnect');
    expect(WidgetButtonRole.none.wire, 'none');
  });

  test('an unknown wire value falls back to the default, not a crash', () {
    expect(WidgetButtonRole.fromWire('surprise'), WidgetButtonRole.adaptive);
    expect(WidgetButtonRole.fromWire(null), WidgetButtonRole.adaptive);
  });

  test('the defaults match what the Kotlin provider assumes unwritten', () {
    // getBoolean("opt_case", true), getBoolean("opt_both", false),
    // getString("opt_button", "adaptive") — a fresh install's widget must
    // not contradict its own settings screen.
    const defaults = WidgetOptions();
    expect(defaults.showCase, isTrue);
    expect(defaults.alwaysBothSides, isFalse);
    expect(defaults.button, WidgetButtonRole.adaptive);
  });

  test('the battery gap threshold matches the Kotlin provider', () {
    expect(
      GlassesBattery.splitThreshold,
      10,
      reason: 'GlassesWidgetProvider.kt hardcodes gapWorthShowing = 10 as a '
          'mirror of this value. If this changes, change it there too — the '
          'in-app gauge and the home screen widget must split the display at '
          'the same difference, or the two will disagree about the same pair '
          'of glasses.',
    );
  });
}
