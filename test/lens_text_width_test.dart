import 'package:flutter_test/flutter_test.dart';
import 'package:g1_extended/models/g1/text.dart';
import 'package:g1_extended/services/lens_text_width.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('falls back to what the code ships with', () async {
    expect(await LensTextWidth.load(), TextMessage.charsPerLine);
  });

  test('remembers a width across a restart', () async {
    await LensTextWidth.set(25);
    expect(LensTextWidth.current, 25);

    // A fresh start reads it back rather than reverting to the default.
    SharedPreferences.setMockInitialValues({'lens_chars_per_line': 25});
    expect(await LensTextWidth.load(), 25);
  });

  test('a corrupted preference is ignored, not obeyed', () async {
    // Ten characters would paginate a sentence into a book, and a hundred
    // would run off a panel that holds about forty.
    SharedPreferences.setMockInitialValues({'lens_chars_per_line': 3});
    expect(await LensTextWidth.load(), TextMessage.charsPerLine);

    SharedPreferences.setMockInitialValues({'lens_chars_per_line': 500});
    expect(await LensTextWidth.load(), TextMessage.charsPerLine);
  });

  test('refuses to store a width nobody could read', () async {
    expect(() => LensTextWidth.set(4), throwsArgumentError);
    expect(() => LensTextWidth.set(200), throwsArgumentError);
  });

  test('resetting comes back to the shipped width', () async {
    await LensTextWidth.set(20);
    await LensTextWidth.reset();

    expect(LensTextWidth.current, TextMessage.charsPerLine);
  });

  test('the candidates are the three the argument is about', () {
    expect(LensTextWidth.candidates, [20, 25, 40]);
  });
}
