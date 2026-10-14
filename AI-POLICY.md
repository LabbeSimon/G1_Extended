# AI agents on this repository

Contributions written with the help of AI agents are **accepted** here.

That was not true while this was being carved out of
[AGiXT/mobile](https://github.com/AGiXT/mobile), which this repository began
as a fork of. Removing 41 000 lines
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
contacts, send SMS, take photos and list files on the phone. The hosts the
app itself can contact are each optional and user-visible:

| Host | Why |
|---|---|
| `api.open-meteo.com` | Weather on the glasses, if enabled |
| `alphacephei.com` | One-off download of the offline speech model |
| `api.github.com` | Update check, if left enabled |
| `api.anthropic.com` | Claude, the assistant, only once you paste an API key |

Every one of them is optional, carries nothing about the user beyond what the
feature plainly needs, and can be turned off. Claude is the strongest case to
watch: it sends the question you asked to Anthropic. It earns its place only
because it is off by default, uses a key *you* obtained and pasted (no account
and no bundled credential — exactly the sign-in the fork was created to
remove), is announced in `PRIVACY.md`, and sits beside the user's own Home
Assistant, which keeps everything on a machine they own. The user-configured
endpoints — a Home Assistant address, a URL inside a card
you installed — are the user's own servers and are not counted here.

What stays rejected on sight is anything the *app* phones home with on its own
behalf: analytics, crash reporting, "anonymous" usage statistics, remote
configuration, an account system, a bundled provider key. Speech recognition
runs on the device and stays there.

If you need data out of the app to debug something, the answer is the
diagnostic report: a JSON file the user generates deliberately, sees the
contents of beforehand, and sends where they choose. Never a request the app
makes on its own behalf.

## Human review

Every change is reviewed by a person before it lands, and the person merging
is responsible for it. An agent's confidence is not evidence. Claims about
hardware behaviour in particular are worth little until someone has put the
glasses on. The Human who push the code is the one who check and test the code.

## Disclosure

If an agent wrote a meaningful part of a commit, note it — a `Co-Authored-By`
trailer is enough. This is for the reader's benefit, not a penalty.
