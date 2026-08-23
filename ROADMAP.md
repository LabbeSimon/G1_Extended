# Roadmap

What is done, what needs a device, and what is open for anyone to take.
Contributions go through pull requests onto `beta` — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Waiting on real glasses

Code complete, verified as far as tests reach, but only a face wearing the
hardware can confirm them:

- [ ] Wake word « souffleur » — the recognizer used to keep its old grammar
      and its old model across changes; both fixed, settings now display
      what is genuinely armed (`lib/services/wake_word_service.dart`)
- [ ] Calendar events on the lens — the manifest was missing
      `WRITE_CALENDAR`, which the plugin's all-or-nothing permission gate
      requires even though the app never writes
- [ ] Battery level surviving a disconnection (the poll used to die with
      its own guard)
- [ ] Both lenses staying in step after a failed write (retries + full
      rewrite when one side missed)

- [ ] The in-app update button, whole loop, at the next release

## In beta, not yet in a stable release

Built and passing their tests, held back from stable until they have run
on real hardware. Both live on the `beta` branch; turn on the beta channel
in Settings → About to get them.

- [ ] **Live translation** of what someone is saying, on the device
      (ML Kit, ~30 MB per language). Adds 24 MB to the app, which is the
      other reason it waits.
- [ ] **Heart rate** from a chest strap or a watch in broadcast mode, as
      `{hr}` in any card

## Blocked on information

- [ ] **Google Maps instructions parsing** — needs a real capture: navigate
      a junction, then Settings → Debug → *Copy navigation capture*, and
      attach the JSON to an issue. The parser will be fixed against what
      Maps actually sends, not what it plausibly sends.
- [ ] **Other sport sensors** — cadence (0x1816), running pace (0x1814):
      same shape as the heart rate work, a parser plus a token
- [ ] **ESP32 / GNSS bike display at 500 ms** — waiting on how the module
      exposes its data (BLE? HTTP on a shared network? serial?)

## Open to contributors

Self-contained, and none needs the glasses' protocol knowledge to start:

- [ ] **More Vosk languages** — the speech model list is two entries
      (`lib/models/speech_model.dart`); adding one is a URL, an id, and
      verifying the wake-word suggestions exist in its lexicon
      (see `lib/services/wake_word_vocabulary.dart` for why)
- [ ] **More firmware language ids** — the caption layout knows four
      (`lib/models/g1/translate.dart`); if you can capture others, PR them
- [ ] **Extensions** — cards for the free catalogue:
      [g1-extensions](https://github.com/LabbeSimon/g1-extensions).
      Declarative, https-only, reviewed by pull request
- [ ] **Screenshots** — `docs/screenshots/README.md` lists what the main
      README wants, from a real phone
- [ ] **Pixel art** — glyphs follow `lib/widgets/pixel_art.dart`; render
      and *look* before proposing (the repo's history shows why)
- [ ] **Translations of the app itself** — the interface is English-only;
      an l10n pass is welcome groundwork

## Investigated, waiting for a volunteer device

- [ ] **Glasses battery in the system's own device list** — Samsung's
      battery widget only lists the Galaxy ecosystem and takes no third
      parties, but Android's CompanionDeviceManager is the official route
      to the same end: associate the glasses as a companion device and
      publish their battery, and they appear under Settings → Connected
      devices like a pair of earbuds (One UI often surfaces that in the
      quick panel too). Pure native work, behaviour varies by One UI
      version, and it cannot be verified without a device in hand.

## Decisions pending

- [ ] Split APKs per ABI — the translation engine pushed the universal APK
      from 59 to 83 MB; per-ABI halves the download
- [ ] What the left-temple hold should do when an assistant is configured
      (today: dictation; candidate: trigger the assistant)

## Done, for the record

Crash reports with reconnect · notes library with pinning and markup ·
notification history with temple-walk · home screen widget with options ·
world clocks (IANA, DST-proof) · speedometer resilience, decimal comma,
clock · lens mirror banner with mode chips · brightness drag tile ·
extension marketplace with terms · in-app updater · live translation ·
reconnection/battery/permission overhauls. Each carries its reasoning in
`git log`.
