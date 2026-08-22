# Privacy Policy

**G1 Extended** — last updated 22 August 2026.

## The short version

This app has no account, no server and no analytics. It does not collect,
store or transmit personal data. Nothing you say, read or display on your
glasses ever leaves your phone.

## What the app can access, and why

The app asks for these permissions. Each one is used only for the feature
named, on your device, and none of it is uploaded anywhere.

| Access | Used for | Leaves the device |
|---|---|---|
| Bluetooth | Pairing and talking to the glasses | No |
| Location | Android requires it to scan for Bluetooth devices, and the weather widget needs a rough position | Only a coordinate rounded to ~1 km, see below |
| Microphone | Dictation, live captions and the optional wake word | No |
| Notification access | Mirroring your phone notifications onto the glasses | No |
| Calendar | Showing the day's agenda on the glasses | No |

## The only three network requests

The app contacts three hosts. All three are optional, and none is operated by us.

**1. `api.open-meteo.com`** — the weather forecast, only if you enable the
weather widget. The request contains your latitude and longitude **rounded to
two decimal places**, roughly a 1 km square. That is precise enough for a
forecast and too coarse to identify a building or an address. Nothing else is
sent: no device identifier, no account, no timestamped history. Open-Meteo's
own privacy policy applies to that request:
<https://open-meteo.com/en/terms>.

**2. `alphacephei.com`** — a one-off download of the offline speech
recognition model, and only if you turn on glasses-microphone dictation or the
wake word. It is a plain file download. No audio and no data about you is sent,
then or ever. After that download, speech recognition runs entirely on your
phone.

**3. `api.github.com`** — an update check, at most once every 12 hours, and
only while "Check for updates" is on in Settings > About. It is an
unauthenticated `GET` for the latest release number of this repository. No
account, no device identifier and nothing about your usage is sent; as with any
web request, GitHub sees the connecting IP address. Nothing is downloaded or
installed automatically: if a newer version exists the app shows a banner and,
if you tap it, opens the release page in your browser. Turn the switch off and
the request is never made.

With the weather widget off, glasses dictation unused and update checks
disabled, the app makes no network requests at all.

## Audio

Speech is recognised on your device. Recordings are transcribed and then
discarded; the audio itself is never written to permanent storage and never
uploaded. Transcripts are kept locally in the dictation history, capped at the
200 most recent entries, and you can clear them at any time from that screen.

## Where your data lives

On your phone, in the app's private storage: notes, checklists, reminders,
dictation history, your settings, and a cached weather reading. Uninstalling
the app deletes all of it. There is no backup to any server, because there is
no server.

## Children

The app is not directed at children and collects nothing from anyone.

## Third parties

There are no advertising networks, no analytics SDKs, no crash reporting and
no tracking of any kind. No data is sold or shared, because none is collected.

## Changes

Any change to this policy will be committed to the repository, so the full
history is public:
<https://github.com/LabbeSimon/G1_Extended/commits/main/PRIVACY.md>

## Contact

Open an issue: <https://github.com/LabbeSimon/G1_Extended/issues>
