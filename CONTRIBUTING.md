# Contributing

Contributions are welcome, including AI-assisted ones — see
[AI-POLICY.md](AI-POLICY.md).

## Reporting something broken

Open an issue. The template asks for a diagnostic report, and it is worth
attaching: almost everything that has gone wrong in this project compiled
cleanly, passed its tests, and still failed on real hardware. Renamed method
channels, a battery timer cancelled by the background service, a speech model
that poisoned every launch, three screens no menu could reach — none of it was
visible from the code. A capture from the device that actually misbehaved is
worth more than any amount of reasoning about it.

Generating one: tap the version ten times in Settings > About, then
Battery frame capture > share. It leaves out anything identifying by default
and lists its contents before writing.

## Sending a change

Fork, branch, open a pull request. Push access is deliberately not granted to
anyone: the CI signs releases with the maintainer's key when a tag is pushed,
so push access would mean the ability to publish a signed build under someone
else's name.

Before opening the PR:

```
flutter analyze   # must report no issues at all
flutter test
```

The CI fails on a single info-level hint. That is on purpose — deprecation
warnings ignored for a year are how a project ends up unable to build at all.

## What gets a change accepted

**It works, and you can say how you know.** Tested on glasses, or derived from
the protocol document — both are fine, they are just worth telling apart.

**Undocumented commands stay undocumented.** `Even Realities G1 BLE
Protocol.txt` marks several commands `??`. Do not invent frames for them. If
you reverse-engineered something, show the capture.

**No new network request** unless it is optional, switchable off, carries
nothing about the user, and is written into [PRIVACY.md](PRIVACY.md). The app
makes three, all of them refusable. Anything that adds a fourth on weaker
terms is refused — analytics, crash reporting, "anonymous" usage statistics,
remote configuration, accounts. If you need data out of the app to debug
something, extend the diagnostic report: a file the user generates
deliberately, sees the contents of, and sends where they choose.

**Tests for anything with logic in it.** Frame builders, parsers, formatting,
matching — all of it is testable without hardware, and all of it has been
wrong at some point.

## Comments

Explain why, not what. The reader can see what the code does. What they cannot
see is the constraint that made it look like that — the byte the protocol
document gets wrong, the OEM that ships no glyphs for Cyrillic, the fact that
a half-extracted model crashes natively and takes the whole app with it.
Several comments in this codebase exist because someone lost an afternoon to
the thing they describe.

## Where things are

| | |
|---|---|
| `lib/models/g1/` | Protocol: frame builders and parsers, no I/O, all testable |
| `lib/services/` | Behaviour: Bluetooth, speech, dashboard content |
| `lib/screens/` | Interface |
| `lib/theme/` | The visual language, in one file |
| `android/app/src/main/cpp/` | Inherited C: LC3 decoding and noise suppression |
| `Even Realities G1 BLE Protocol.txt` | What is known about the wire format |
