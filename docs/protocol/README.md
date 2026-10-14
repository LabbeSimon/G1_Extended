# The G1 protocol as the official Even app 1.6.5 speaks it

These files describe the Bluetooth protocol between the Even G1 glasses and
the official Even app, version 1.6.5, as analysed in that app. They exist so
that this app can interoperate with the glasses as the official one does.

Protocol facts only. No code from the official app is reproduced here, and
nothing from it is redistributed: byte layouts, values, sides, timings and the
order of exchanges, with the names of the functions involved so that anyone
can check them against the same version.

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

- Every timeout, delay and retry count in these files is the value the
  official app actually applies.
- "L" and "R" are the left and right temples, each its own BLE connection.
  "L then R" means the right temple only gets the frame once the left one
  answered as expected.
- Most replies echo the command in byte 0 and carry `0xC9` for success,
  `0xCA` for failure, `0xCB` for "continue" in multi-packet lists. The
  teleprompter is the exception: it answers `0x00` for success.

## Every feature re-checked

[audit.md](audit.md) lists each feature this app has, compared with the
official app 1.6.5: what was fixed, what differs but works and is left alone,
what is debug-only, and what is not implemented.

## What this changes for this app

| Topic | Official app 1.6.5 | This app |
|---|---|---|
| Recordings (`0x1E` sub `0x02`) | total at bytes 5–6, packet index at 7–8, done when the count reaches total, first 400 bytes dropped; list requested on connection and after each download | **Fixed** to match: `VoiceNoteDownload`, list requested on connection and after each saved recording |
| Teleprompter | Its own `0x09` mode: five lines, a progress bar, one-row scroll animation, a heartbeat every 2 s | **Added** as "Glasses teleprompter" (beta, waits for real glasses); voice mode starts in the AI mode (`0x82`), the only one in which the official app opens the microphone, without the highlight dot; text pages remain as the fallback |
| Translation (`0x1C`, `0x0F`, `0x0D`) | Start request `0x50` to the right temple, `1C 00`, both areas cleared with a lone `\r`, full redraws of up to 193 bytes per packet with lines joined by `\r`; `1C 01` then `18` to close | **Aligned** with it, with 25 languages; it used to send a stray position byte and never closed the glasses' translation screen |
| Assistant | Even AI, through Even's servers | **Added** Claude with the user's own API key, off until a key is pasted; or the user's own Home Assistant and its agents |
| End of an answer | `exitAI`: `54 06 00 seq 01 00` (status 0) to L, then R if L took it, up to 3 tries 100 ms apart; `18` only when a session hangs | **Aligned**: the AI screen the long press opened is closed the same way once the answer has been read, with `18` if the glasses refuse it |
| `0x4B` notification | Left temple only, byte 1 is `0x00`, each packet acknowledged, six attempts | Both temples, byte 1 is `0x01`. Confirmed working on glasses (see PROTOCOL_NOTES.md), left unchanged |
| `0x4C` dismiss | Five bytes: `4C` + message id (u32 big-endian), left temple | A bare `4C` to both temples, never tried |
| `0x06` sub `0x01` time and weather | 22 bytes: a date-format byte at the end | 21 bytes, the older layout. Works; not changed |
| `0x37` uptime | Reads the u32 at bytes 2–5 | Not used |
| Characters per line | No fixed count: wrapped by pixel width (450 px, font size 20) | Text command keeps its setting; the glasses teleprompter wraps at 90 % of it |
| `0x25` | The teleprompter's heartbeat only; the general keep-alive is `0x2C`/`0x2B` polling while the link is idle | `0x25` every 5 s to both temples as a keep-alive. Works; not changed |
| `0x4E` text | Not built anywhere in 1.6.5 (`0x54` sub `0x03` replaced it) | Still used for all text. Works |
| `0x15` bitmap | Used for font upload only; no full-screen bitmap | Used for bitmaps, inherited. Works |
| Firmware update | Nordic SMP (McuMgr) on its own GATT service, not the UART channel | Not implemented |
