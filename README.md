# G1 Extended

An Android companion app for [Even Realities G1](https://www.evenrealities.com) smart glasses.
No account. No telemetry. Nothing leaves your phone.

## What it does

**Glasses**
- Pairs with both temples over BLE and reconnects on its own
- Battery level for each side
- Brightness, silent mode, head-up angle, dashboard position
- Keeps the connection alive from a background service

**On the display**
- A dashboard with the time, weather, your agenda, checklists and reminders
- Phone notifications forwarded in real time, filtered per app
- Turn-by-turn directions, read from whatever navigation app you already use
- Optional live speed readout from GPS
- Live captions from the glasses microphone
- A teleprompter that follows your voice, or a set pace, or your thumb
- Your own lines on the lens, built from live values or a URL you choose
- Optionally, questions answered by a model you host or chose — never a
  bundled one, and only ever the transcribed text, never the audio
- Dictation: hold a temple touchpad, speak, see the text on the lens

**Voice**
- Speech recognition runs on the device, through Vosk or the platform recogniser
- Optional wake word
- No audio is ever uploaded

## What it does not do

This is a fork of [AGiXT/mobile](https://github.com/AGiXT/mobile) with everything
that was not about the glasses taken out:

| Removed | Why |
|---|---|
| AI assistant and chat | The point of the fork |
| Accounts, login, OAuth | The app has no server to log into |
| Solana wallet integration | Nothing to do with glasses |
| Remote command execution | The server could read contacts, send SMS, take photos, read files |
| Wear OS companion app | Not a G1 |
| The iOS project | Never compiled, and could not work: notification access, the background service, the app list and the offline speech model are all Android-only |
| Android digital assistant | Existed only to launch the AI |
| Discord build webhook | Sent commit messages and usernames to a third-party chat |

Android permissions went from 33 to 18. The app makes three network requests, all
optional:

- `api.open-meteo.com` for the weather widget, if you enable it
- `alphacephei.com` once, to download the offline speech model
- `api.github.com` to check for a newer release, if you leave that on

## Privacy

No account, no telemetry, three optional network requests. The full statement is
in [PRIVACY.md](PRIVACY.md).

## Contributing

AI-assisted contributions are accepted. See [AI-POLICY.md](AI-POLICY.md) for
what is expected, and for the one rule that is not negotiable: no accounts,
no telemetry, no phoning home.

## Build

```
flutter pub get
flutter build apk --release
```

CI builds an APK on every push and attaches it as an artifact. A release is
cut only by pushing a tag, so ordinary commits do not create versions:

```
git tag v1.1.0
git push origin v1.1.0
```

## Signing

`android/keystore.properties` and `android/app/keystore/` are gitignored.
Release builds fall back to the debug key when no keystore is present.
Create your own:

```
keytool -genkey -v -keystore android/app/keystore/release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias release
```

Then write `android/keystore.properties`:

```
storePassword=...
keyPassword=...
keyAlias=release
storeFile=../app/keystore/release.jks
```

## Protocol

`Even Realities G1 BLE Protocol.txt` documents the BLE commands this app uses.

Hardware figures that shape the code, from the manufacturer's own
specifications:

| | |
|---|---|
| Display | 640 × 200, monochrome green micro LED, 25° field of view |
| Refresh | 20 Hz — which is why directions and speed are throttled rather than redrawn on every update |
| Scripts | Latin, Japanese, Korean and simplified Chinese. Cyrillic, Arabic, Hindi, Bengali and traditional Chinese are not drawable and are refused before sending |
| Battery | 160 mAh in the glasses, 2000 mAh in the case |
| Microphones | Two |

The bitmap helper works on a 576 × 136 canvas, which is not the display
resolution above. Whether that is an inherited mistake or the image command
addressing a sub-region is untested.

## Third-party code

What ships inside the APK that someone else wrote is listed in
[THIRD_PARTY.md](THIRD_PARTY.md), and shown in the app under
Settings > About > Licence.

## Licence and provenance

BSD 2-Clause. See [LICENSE](LICENSE), whose copyright notice must travel with
any copy of this code or of a binary built from it.

The lineage, since this repository is no longer marked as a fork and nothing
else records it:

- the copyright notice names **even-realities**
- **[AGiXT/mobile](https://github.com/AGiXT/mobile)** built the AI assistant on
  top of it, starting May 2025
- this repository removed that assistant and everything else unrelated to the
  glasses

Roughly 12 000 of the surviving lines are inherited, mostly the BLE layer and
the LC3 decoder. That work is not mine and the licence is theirs.
