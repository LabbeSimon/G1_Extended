# Third-party code

What ships inside the APK that someone else wrote, and under what terms.
The app also shows all of this at runtime, under Settings > About > Licence,
because both Apache 2.0 and the BSD licences here require the notice to travel
with the binary and not only with the source.

## Compiled into the app

| Component | Licence | Copyright |
|---|---|---|
| [liblc3](https://github.com/google/liblc3) | Apache 2.0 | Google LLC |
| rnnoise | BSD 3-Clause | Octasic Inc., Jean-Marc Valin |
| [Vosk](https://alphacephei.com/vosk/) | Apache 2.0 | Alpha Cephei Inc. |

`liblc3` decodes the audio the glasses microphone sends. `rnnoise` cleans it
up. Both are vendored as C sources under `android/app/src/main/cpp` and are
invisible to Flutter's licence collection, which only sees Dart packages —
hence `lib/utils/third_party_licences.dart`, which registers them by hand.

Vosk arrives as a native library through its Flutter plugin. The acoustic
model it downloads on first use is separately licensed by Alpha Cephei under
Apache 2.0.

## Dart packages

Flutter collects these automatically; the same Licence screen lists every one
with its full text. `flutter pub deps` prints the tree.

## This application

BSD 2-Clause, see [LICENSE](LICENSE). The Bluetooth layer and the LC3
integration are inherited from [AGiXT/mobile](https://github.com/AGiXT/mobile),
whose copyright notice names even-realities. See the provenance section of the
[README](README.md).

## Not included

The app is a third-party client. It carries no Even Realities artwork,
branding or firmware, and is not affiliated with or endorsed by them. "Even
Realities" and "G1" are used only to say what hardware the app talks to.
