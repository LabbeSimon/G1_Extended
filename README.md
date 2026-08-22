# G1 Extended

A companion app for [Even Realities G1](https://www.evenrealities.com) smart glasses.
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

CI builds an APK on every push and publishes a release from `main`.

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

## Licence

See [LICENSE](LICENSE). Upstream work belongs to the AGiXT authors.
