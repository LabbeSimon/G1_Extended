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
| Location | Android requires it to scan for Bluetooth devices, the weather widget needs a rough position, and the optional speed readout reads GPS | Only a coordinate rounded to ~1 km, for the weather. Never for speed |
| Microphone | Dictation, live captions and the optional wake word | No |
| Notification access | Mirroring your phone notifications onto the glasses | No |
| Calendar | Showing the day's agenda on the glasses | No |

## Every network request, and what triggers it

The app contacts nothing on its own schedule except the update check below,
and that one has a switch. Everything else happens only when you press the
thing that needs it. None of these hosts is operated by us.

**`api.open-meteo.com`** — the weather forecast, only if you enable the
weather widget. The request contains your latitude and longitude **rounded to
two decimal places**, roughly a 1 km square — precise enough for a forecast,
too coarse to identify a building. No device identifier, no account, no
timestamped history. Open-Meteo's policy: <https://open-meteo.com/en/terms>.

**`alphacephei.com`** — a one-off download of the offline speech recognition
model, only if you turn on glasses-microphone dictation or the wake word. A
plain file download; no audio and nothing about you is sent, then or ever.
After it, speech recognition runs entirely on your phone.

**`api.github.com`** — the update check, at most once every 12 hours, only
while "Check for updates" is on in Settings > About. An unauthenticated GET
for the latest release number; GitHub sees the connecting IP, as with any web
request. Nothing downloads by itself. Tapping the update banner downloads
the APK from the release **and opens Android's own install sheet — the
system confirms every install itself**; a long-press opens the release page
instead. Switch off, and the request is never made.

**`raw.githubusercontent.com`** — the extension catalogue, fetched only when
you press "Fetch the catalogue" on the Extensions screen. Never polled in
the background.

**Addresses inside cards you install or write** — a custom card, yours or an
extension's, may read a value from an https URL. The exact URLs are visible
on each card in "My cards" before and after installing, and each card can be
disabled. These are fetched at the card's stated interval while the card is
enabled — this is the one category that polls, it polls the address you
approved, and extensions may not poll more often than every five minutes.

## Speed

The optional speed readout turns GPS into a number of km/h on your phone and
draws that number on the lens. No position, no track, no history: nothing is
stored and nothing is sent. It is off by default, and while it is on the app
holds a foreground service so Android keeps delivering fixes with the screen
locked — otherwise the readout would freeze the moment you pocket the phone.

## Audio

Speech is recognised on your device. Recordings are transcribed and then
discarded; the audio itself is never written to permanent storage and never
uploaded. Transcripts are kept locally in the dictation history, capped at the
200 most recent entries, and you can clear them at any time from that screen.

## Diagnostics

There is no telemetry. Nothing is collected in the background and nothing is
sent anywhere on its own.

Instead there is a diagnostic report you can generate yourself. It lives
behind developer options, which are hidden until you tap the version in
Settings > About ten times, so nobody meets it by accident.

By default the report leaves out anything that would tie it to you or to your
hardware: your phone's manufacturer and model, its exact OS build, its screen
size, the app's package name, and the Bluetooth names of your glasses — which
carry their serial number. What remains is the app version, the operating
system family, whether the glasses are connected, battery percentages, and any
raw protocol frames you chose to record. That is enough to decode a protocol
problem and not enough to identify a person.

You can switch that off if you are debugging your own device and want the
details. The app lists exactly what the file contains before writing it, saves
it as JSON you own, and hands it to your system share sheet. Where it goes is
entirely your decision.

No location, no contacts, no audio, ever. Recording protocol frames is off by
default and only records while you leave it on.

### The action journal

Behind developer mode, then ten taps on the protocol bench's title, sits a
journal that records the app's own actions — each Bluetooth write's command
byte and length, heartbeats, syncs, connection events with their reasons.
It exists to chase connection bugs, and three properties keep it honest:
it never records content (that a notification was sent, never what it
said); it never leaves the device unless you copy it out yourself; and it
switches itself off 24 hours after being enabled, so a journal forgotten
on cannot quietly record a stranger's week — the stranger being future
you.

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
