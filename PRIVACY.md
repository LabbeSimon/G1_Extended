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

**Your own endpoints.** Two features send data to a host you choose and the
app has never heard of: a custom card pulling `{value}` from a web address, and
the assistant.

The assistant is off, and has no default host. Nothing happens until you type
an address in. What is sent is the **text** of your question — the audio never
travels, because speech is turned into text on the phone by the offline model
first. Point it at a machine on your own network and the question does not
leave your home. Point it at a commercial service and that is a decision you
made in a field you filled. An API key, if the service needs one, is kept in
the Android keystore. These are the only requests the app makes on your behalf rather
than its own: it never adds one, never picks the host, and fetches no more
often than the interval you set. We have no idea what those addresses are and
no way to find out.

With the weather widget off, glasses dictation unused, update checks disabled,
no assistant configured and no custom card using a source, the app makes no
network requests at all.

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
