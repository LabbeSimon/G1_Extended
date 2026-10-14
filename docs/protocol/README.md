# The G1 protocol as the official Even app 1.6.5 speaks it

These files describe the Bluetooth protocol between the Even G1 glasses and
the official Even app, version 1.6.5, read by static analysis of that app:
its Dart code (compiled ahead of time, decompiled with blutter) and its native
Android layer (JADX). They exist so that this app can interoperate with the
glasses as the official one does.

Protocol facts only. No code from the official app is reproduced here, and
nothing from it is redistributed: byte layouts, values, sides, timings and the
order of exchanges, with the names of the functions they were read in so that
anyone with the same APK can check them.

**What this is worth.** A `[certain]` fact is something the official app
certainly does. It is not yet something the glasses were seen to accept:
none of this has been compared with a capture, unless a line says so. The
tiers of [PROTOCOL_NOTES.md](../PROTOCOL_NOTES.md) still apply — a byte read
in an app is evidence, a byte that works on a face is proof.

## Files

| File | Covers |
|---|---|
| [transport.md](transport.md) | GATT service, scan, connection, the two request layers, inbound `0xF5` events, microphone audio (`0xF1`), device info (`0x2C`), keep-alive, font upload, firmware update, `#` commands |
| [settings.md](settings.md) | Brightness, silent mode, head-up angle and type, wear detection, display height, double tap, press-and-hold, language, serial numbers, statistics, reset |
| [teleprompter.md](teleprompter.md) | `0x09` start, screens, run dot, stop; `0x24` pause; `0x25` heartbeat; screen layout and progress |
| [even-ai-transcribe-translate.md](even-ai-transcribe-translate.md) | Even AI (`0x54`, `0x55`, `0x56`) and its full flow, transcription (`0x52`, `0x53`), translation (`0x1C`, `0x0F`, `0x0D`), microphone (`0x0E`), feature start and exit (`0x18`, `0x50`, `0x51`) |
| [notes-notifications-dashboard-navigation.md](notes-notifications-dashboard-navigation.md) | Recordings and text notes (`0x1E`, `0x21`), notifications (`0x4B`, `0x4C`), allowlist (`0x04`), dashboard (`0x06`, `0x22`), navigation (`0x0A`) |

## Reading the numbers

- Small integers that the app keeps in a Dart list, or passes as an argument,
  appear doubled in the disassembly (Dart's tagged small integers). Every
  value in these files is the real one. Defaults written inside a function,
  values used in arithmetic, and `Duration` constants (stored in microseconds)
  are not doubled.
- "L" and "R" are the left and right temples, each its own BLE connection.
  "L then R" means the right temple only gets the frame once the left one
  answered as expected.
- Most replies echo the command in byte 0 and carry `0xC9` for success,
  `0xCA` for failure, `0xCB` for "continue" in multi-packet lists. The
  teleprompter is the exception: it answers `0x00` for success.

## What this changes for this app

| Topic | Official app 1.6.5 | This app |
|---|---|---|
| Recordings (`0x1E` sub `0x02`) | total at bytes 5–6, packet index at 7–8, done when the count reaches total, first 400 bytes dropped; list requested on connection and after each download | **Fixed** to match: `VoiceNoteDownload`, list requested on connection and after each saved recording |
| Teleprompter | Its own `0x09` mode: five lines, a progress bar, one-row scroll animation, a heartbeat every 2 s | **Added** as "Glasses teleprompter" (beta, waits for real glasses); text pages remain as the fallback |
| Assistant | Even AI, through Even's servers | **Added** Claude with the user's own API key, off until a key is pasted; self-hosted endpoint unchanged |
| `0x4B` notification | Left temple only, byte 1 is `0x00`, each packet acknowledged, six attempts | Both temples, byte 1 is `0x01`. Confirmed working on glasses (see PROTOCOL_NOTES.md), left unchanged |
| `0x4C` dismiss | Five bytes: `4C` + message id (u32 big-endian), left temple | A bare `4C` to both temples, never tried |
| `0x06` sub `0x01` time and weather | 22 bytes: a date-format byte at the end | 21 bytes, the older layout. Works; not changed |
| `0x37` uptime | Reads the u32 at bytes 2–5 | Not used |
| Characters per line | No fixed count: wrapped by pixel width (450 px, font size 20) | Text command keeps its setting; the glasses teleprompter wraps at 90 % of it |
| `0x25` | The teleprompter's heartbeat only; the general keep-alive is `0x2C`/`0x2B` polling while the link is idle | `0x25` every 5 s to both temples as a keep-alive. Works; not changed |
| `0x4E` text | Not built anywhere in 1.6.5 (`0x54` sub `0x03` replaced it) | Still used for all text. Works |
| `0x15` bitmap | Used for font upload only; no full-screen bitmap | Used for bitmaps, inherited. Works |
| Firmware update | Nordic SMP (McuMgr) on its own GATT service, not the UART channel | Not implemented |
