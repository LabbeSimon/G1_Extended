# G1 Extended

> **Not an official app.** G1 Extended is an independent companion for the
> Even Realities G1, not made by, affiliated with, or endorsed by Even
> Realities. Free, no accounts, no telemetry — and everything about it,
> including its extension catalogue, is forbidden to be sold.
> See [TERMS.md](TERMS.md).

[![Build](https://github.com/LabbeSimon/G1_Extended/actions/workflows/build_apk.yml/badge.svg)](https://github.com/LabbeSimon/G1_Extended/actions/workflows/build_apk.yml)
[![Release](https://img.shields.io/github/v/release/LabbeSimon/G1_Extended?label=release)](https://github.com/LabbeSimon/G1_Extended/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/LabbeSimon/G1_Extended/total?label=downloads)](https://github.com/LabbeSimon/G1_Extended/releases)
[![Licence](https://img.shields.io/badge/licence-BSD--2--Clause-blue)](LICENSE)
[![Android](https://img.shields.io/badge/android-7.0%2B-brightgreen)](#build)
[![Telemetry](https://img.shields.io/badge/telemetry-none-brightgreen)](PRIVACY.md)

An alternative, open-source Android client for the
[Even Realities G1](https://www.evenrealities.com) smart glasses.

It removes the telemetry and the account the original client came with, and
gives back a device that works entirely on its own. Working from a
reverse-engineered BLE protocol — two Nordic UART radios, one per temple — it
lets you force HUD layouts the official app does not expose, read hardware
events it discards, and push your own data to the lens, including from a
microcontroller of your own.

No account. No telemetry. Nothing leaves your phone.

## Download

**[Latest release →](https://github.com/LabbeSimon/G1_Extended/releases/latest)**
— the signed APK is attached to every release, and once installed the app
updates itself from its banner: one tap downloads the new version and opens
Android's installer.

Testing the next version early: pre-releases are published on the
[releases page](https://github.com/LabbeSimon/G1_Extended/releases) from the
`beta` branch. They never appear in the in-app update check — stable stays
stable unless you opt in by hand.

## The app in pictures

<!-- Screenshots land in docs/screenshots/ — see the README there for the
     expected names. Until they do, the sections below say more than any
     placeholder would. -->

*Screenshots are coming with the 1.1.2 release; the layout they will show
is described honestly in the sections below.*

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

## Running in the background

The glasses need the phone to keep two Bluetooth links open and to answer a
heartbeat, or the firmware drops the connection after 32 seconds. That is not
something Android lets an app do quietly, so it runs as a foreground service
with a persistent notification. There is no way around the notification and
no attempt to hide it.

What that costs, and what it does not:

- **Heartbeat every 15 seconds while connected.** Required by the protocol.
- **Reconnect attempts while disconnected**, spaced by how long the glasses
  have been gone: every 2 seconds for the first half minute, then easing to
  once every 5 minutes after an hour. Roughly 115 attempts in the first hour
  of absence, then 12 an hour. Opening the app brings the next one forward.
- **Battery level read every 90 seconds while connected.**
- **No location polling.** Location is read once when weather is refreshed,
  and continuously only while the speedometer card is on screen.
- **No background network activity.** Nothing is synced, uploaded or
  reported. See [PRIVACY.md](PRIVACY.md).

### Doze, App Standby and OEM battery managers

Android suspends background work when the screen has been off for a while,
and several manufacturers go considerably further than Android does. A
foreground service survives Doze; it does not always survive an OEM task
killer.

Ask for the battery optimisation exemption when the app offers it — it is in
the permissions screen, and without it the connection will drop whenever the
phone sleeps. On devices from manufacturers that ignore that exemption, the
app also has to be allowed to start automatically and be locked in the recent
apps list. Those settings live in different places on every brand;
[dontkillmyapp.com](https://dontkillmyapp.com) lists them per manufacturer.

If the connection drops overnight despite all of that, it is worth reporting
with the device model — that is the kind of thing no amount of reading the
code will reveal.

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

## By the numbers

Counted from the working tree, not estimated.

| | |
|---|---|
| Dart | 18 800 lines across 100 files |
| Native C and C++ | 26 300 lines — the LC3 decoder and noise suppression, inherited |
| Tests | 215, in 26 files |
| Static analysis | 0 issues; CI fails on a single info-level hint |
| Android permissions | 18, down from 33 |
| Dependencies | 29, down from 43 |
| Network requests | 3, every one optional and switchable off |
| APK | 56 MB, arm64 and armeabi-v7a |

Roughly 12 000 of the surviving Dart lines are inherited from
[AGiXT/mobile](https://github.com/AGiXT/mobile), mostly the Bluetooth layer.
The 35 commits since the fork removed 41 000 lines and added the glasses
features listed above.

The badges above are rendered by GitHub when you read this page. They are not
part of the app and the app never contacts those hosts — see
[PRIVACY.md](PRIVACY.md) for the three it does contact.

## Contributing

Fork, branch, pull request — see [CONTRIBUTING.md](CONTRIBUTING.md). Bug
reports go through [issues](https://github.com/LabbeSimon/G1_Extended/issues),
and the template asks for a diagnostic report because almost everything that
has broken here compiled cleanly and passed its tests first.

AI-assisted contributions are accepted; [AI-POLICY.md](AI-POLICY.md) says what
is expected of them, and states the one rule that is not negotiable: no
accounts, no telemetry, no phoning home.

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

`android/keystore.properties` and `android/app/keystore/` are gitignored, and
CI deletes the key it restores as soon as the build ends. Without a key the
build still succeeds and produces a debug-signed APK, so a fork or a pull
request is never blocked — but a debug-signed APK must not be published.

That last point is the one that bites. Android ties an app's identity to its
signature: an APK signed with one key cannot be updated by an APK signed with
another. Publish once with the debug key and every later release becomes an
uninstall-and-lose-your-data affair. Sign properly before the first release,
and keep that key somewhere you will still have it in five years.

To create one:

```
keytool -genkeypair -v -keystore android/app/keystore/release.jks \
  -alias release -keyalg RSA -keysize 4096 -validity 10000
```

Then write `android/keystore.properties`:

```
storePassword=...
keyPassword=...
keyAlias=release
storeFile=../app/keystore/release.jks
```

For CI, add two repository secrets: `KEYSTORE_BASE64`, the keystore as
`base64 -w0`, and `KEYSTORE_PASSWORD`.

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
