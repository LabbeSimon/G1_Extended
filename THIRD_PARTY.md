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

## Protocol knowledge, not code

Nothing here ships in the APK. These projects worked out parts of the BLE
protocol this app speaks, and the findings were reimplemented from what they
describe rather than copied — which is also why they are named here rather
than in the licence screen.

| Project | What it settled |
|---|---|
| [even-utils](https://github.com/radioegor146/even-utils) — Egor Koleda | The dashboard's second pane: news cards and the walking map, under sub-commands 0x05 and 0x07 |
| [openg1-sdk](https://github.com/gabrielevierti/openg1-sdk) — Gabriele Vierti | The 576 × 136 canvas, the 488 pixel text column, and the table of 0xF5 event sub-codes |
| [g1bridge](https://github.com/Artem1bar/g1bridge) — MIT | Forty characters a line, five lines a screen, confirmed on hardware |
| [even_glasses](https://github.com/emingenc/even_glasses) | The notification and text commands this app's own senders are built on |

## Not included

The app is a third-party client. It carries no Even Realities artwork,
branding or firmware, and is not affiliated with or endorsed by them. "Even
Realities" and "G1" are used only to say what hardware the app talks to.
