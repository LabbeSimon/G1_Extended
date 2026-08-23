import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/widgets/battery_gauge.dart';

/// The home screen widget's provider is Kotlin and cannot share code with
/// the app, so its display rules are copies. These tests exist to make the
/// copies impossible to change apart by accident: break one of these and the
/// failure message names the file holding the twin.
void main() {
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
