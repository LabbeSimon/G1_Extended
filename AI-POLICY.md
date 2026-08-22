# AI agents on this repository

Contributions written with the help of AI agents are **accepted** here.

That was not true while the fork was being carved out of
[AGiXT/mobile](https://github.com/AGiXT/mobile). Removing 41 000 lines
touches everything at once, and an agent working in the middle of it would
have been reasoning about a codebase that no longer existed by the time it
finished. The heavy lifting is done, so that objection is gone.

## What is expected of any contribution

The same things, whoever or whatever wrote it:

- `flutter analyze` reports **no issues**. Not "warnings only" — none. The CI
  fails on a single info-level hint, deliberately.
- `flutter test` passes.
- New protocol work cites `Even Realities G1 BLE Protocol.txt`. Commands the
  document marks `??` are undocumented: do not invent frames for them. If you
  reverse-engineered something, say so and show the capture.
- New dependencies are justified in the pull request. This project went from
  43 packages to 27 on purpose.

## The one rule that is not negotiable

**No accounts, no telemetry, no phoning home.**

This fork exists because the upstream app shipped a server that could read
contacts, send SMS, take photos and list files on the phone. The app makes
exactly two network requests, both optional and both user-visible:

| Host | Why |
|---|---|
| `api.open-meteo.com` | Weather on the glasses, if enabled |
| `alphacephei.com` | One-off download of the offline speech model |

Anything that adds a third is rejected on sight — analytics, crash reporting,
"anonymous" usage statistics, remote configuration, an account system. Speech
recognition runs on the device and stays there.

## Human review

Every change is reviewed by a person before it lands, and the person merging
is responsible for it. An agent's confidence is not evidence. Claims about
hardware behaviour in particular are worth little until someone has put the
glasses on.

## Disclosure

If an agent wrote a meaningful part of a commit, note it — a `Co-Authored-By`
trailer is enough. This is for the reader's benefit, not a penalty.
