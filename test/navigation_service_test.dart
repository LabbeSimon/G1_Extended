import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/services/navigation_service.dart';

/// Formatting is the part worth pinning down: the two notification fields
/// carry different things depending on the app's version and the phone's
/// language, and neither is guaranteed to be there.
void main() {
  String? format(String? title, String? content) =>
      NavigationService.format(title, content);

  test('joins the manoeuvre and the road on two lines', () {
    expect(format('In 200 m turn right', 'Rue de la Paix'),
        'In 200 m turn right\nRue de la Paix');
  });

  test('falls back to whichever field is present', () {
    expect(format('Turn left', null), 'Turn left');
    expect(format(null, 'Rue de Rivoli'), 'Rue de Rivoli');
    expect(format('', 'Rue de Rivoli'), 'Rue de Rivoli');
  });

  test('gives nothing when both fields are empty', () {
    expect(format(null, null), isNull);
    expect(format('', '   '), isNull);
  });

  test('does not repeat a road that appears in both fields', () {
    expect(format('Rue de la Paix', 'Continue on Rue de la Paix'),
        'Continue on Rue de la Paix');
    expect(format('Continue on Rue de la Paix', 'Rue de la Paix'),
        'Continue on Rue de la Paix');
  });

  test('trims the whitespace the notification carries', () {
    expect(format('  Turn right  ', '  Main Street '),
        'Turn right\nMain Street');
  });

  test('recognises the navigation apps it supports', () {
    expect(NavigationService.supportedApps.containsKey(
        'com.google.android.apps.maps'), isTrue);
    expect(NavigationService.supportedApps.containsKey('com.waze'), isTrue);
    expect(NavigationService.supportedApps.containsKey('com.whatsapp'),
        isFalse);
  });
}
