# Every feature, re-checked against the official app 1.6.5

Each frame this app sends to or reads from the glasses, compared with what the
official Even app 1.6.5 does (the files beside this one). Verdicts:

- **matches** — this app already did what the official app does.
- **fixed** — it differed in a way that would misbehave; now aligned. The
  commit is on the `beta` branch.
- **differs, works** — it differs, but this app's version is confirmed on real
  glasses; left unchanged on purpose.
- **debug only** — only reachable from Settings → Debug, not a real feature.
- **needs a capture** — cannot be settled without a Bluetooth trace on the
  hardware.

Nothing here has been checked against a capture unless it says "confirmed on
glasses".

## Fixed this pass

| Feature | Frame | What was wrong |
|---|---|---|
| Voice notes download | `0x1E` sub `0x02` | total/index read one byte early, chunks ordered by the wrong byte, the opening 400-byte click kept |
| Voice notes sync | `0x1E` sub `0x01` / `0x21` | only the newest note fetched, nothing made while disconnected; now the list is asked for on connect and after each save, duplicates skipped by crc |
| Teleprompter | `0x09`, `0x24`, `0x25` | the feature did not exist; added as the glasses' own scrolling screen, voice mode as the AI mode `0x82` |
| Live captions / translation | `0x1C`, `0x0F`, `0x0D` | a stray position byte, no packet splitting, the translation screen never closed, 4 languages instead of 25 |
| Glasses microphone | buffering | voice mode and captions got no audio unless dictation was set to the glasses mic (off by default) |
| Head-up angle readback | `0x32` | read the level byte as the angle |
| Display position readback | `0x3B` | required a `0xC9` status the firmware does not send there |
| Display position write | `0x26` sub `0x02` | wrapped in a debug-mode (`0xF4`) the official app never sends |
| Wear detection readback | `0x3A` | treated the `0xFF` "on" value as off |
| Silent mode | `0x03` | sent two bytes; the official app sends three |
| Uptime | `0x37` | read from byte 1; the official app reads byte 2 after a status byte |
| Battery voltage | `0x2C` | read from byte 3; it is byte 4, as `(v*100)-200` |
| Notification allowlist | `0x04` | keys were capitalised (`Call_enable`, `List`); the firmware's are lower-case |
| Time and weather | `0x06` sub `0x01` | 21 bytes; the official app sends 22, with a date-format byte |
| Touchpad / state events | `0x0F` | half the `0xF5` sub-codes were unnamed or mislabelled |

## Differs, works — left unchanged

| Feature | Frame | Note |
|---|---|---|
| Notifications | `0x4B` | This app sends to both temples with byte 1 = `0x01`; the official app sends to the left only with byte 1 = `0x00` and a per-packet ack. This app's version is the one **confirmed on glasses** (PROTOCOL_NOTES.md); the four-byte header was the real former bug. |
| Text on the lens | `0x4E` | The official app 1.6.5 has no general text command (it uses `0x54` sub `0x03` for AI answers only). This app's `0x4E` path drives every screen and works; replacing it would be a rewrite with nothing to gain. |
| Pinned note slots | `0x1E` sub `0x03` | The four dashboard notes use an inherited frame shape that differs from the official `recordId/mode/len/body/len/title`. The slots work today; a capture is needed before changing a working feature. |
| Bitmap transfer | `0x15` / `0x16` | Inherited full-screen bitmap path. The official app uses `0x15` for font upload only (198-byte chunks). This app's bitmap works; left as is. |
| Keep-alive | `0x25` every 5 s | This app sends the teleprompter heartbeat as a general keep-alive to both temples. The official app instead polls `0x2C`/`0x2B` while the link is idle. This app's keep-alive works. |
| Dashboard layout | `0x06` sub `0x06` | Byte-for-byte the official frame (`06 07 00 seq 06 mode pane`). matches. |
| Zero-angle calibration | `0x39`/`0x50`/`0x10` | Replays the official handshake; matches. |
| Brightness | `0x01` / `0x29` | matches. |

## Debug only

| Feature | Frame | Note |
|---|---|---|
| Calendar pane | `0x06` | `CalendarItem.constructDashboardCalendarItem` is only called from Settings → Debug, and its layout does not match the official `0x06` sub `0x03`. The real dashboard never sends it. Not wired, so not fixed; the official format is in [notes-notifications-dashboard-navigation.md](notes-notifications-dashboard-navigation.md) for whoever wires it. |
| `0x4C` dismiss, news/stock/map panes | various | Present as debug buttons or `even-utils` ports, never on a real path. Official formats documented. |

## Not implemented

Firmware update (`0x17` then Nordic SMP on its own GATT service) and font
upload (`0x15`/`0x20`/`0x16`). Documented, not built. Navigation (`0x0A`) is
now driven without its map images: open, route info, heartbeat, arrival, exit.
