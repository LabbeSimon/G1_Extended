import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The LC3 decoder is bound by name. JNI looks for
/// `Java_<package of Cpp.kt>_Cpp_<method>`, and when the package moved the
/// C++ names stayed behind: every decode of the glasses' audio then threw
/// an UnsatisfiedLinkError that killed the app outright. Nothing in Dart can
/// see that happen, so it is pinned here instead.
void main() {
  test('the C++ entry points carry the package of Cpp.kt', () {
    final kotlin = File(
      'android/app/src/main/kotlin/fr/simonlabbe/g1extended/cpp/Cpp.kt',
    ).readAsStringSync();
    final package = RegExp(r'^package\s+([\w.]+)', multiLine: true)
        .firstMatch(kotlin)!
        .group(1)!;
    final prefix = 'Java_${package.replaceAll('.', '_')}_Cpp_';

    final cpp =
        File('android/app/src/main/cpp/liblc3.cpp').readAsStringSync();
    final natives = RegExp(r'external fun (\w+)')
        .allMatches(kotlin)
        .map((m) => m.group(1)!)
        .toList();

    expect(natives, isNotEmpty);
    for (final name in natives) {
      expect(cpp, contains('$prefix$name('), reason: name);
    }
  });
}
