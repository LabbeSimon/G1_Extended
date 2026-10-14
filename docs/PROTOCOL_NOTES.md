# What this app knows about the protocol, and how well

Nobody outside Even Realities has the documentation. What follows is what
this application does, sorted by how much it is worth believing — because a
byte that works on a pair of glasses and a byte that looks right in a
capture are not the same kind of fact, and treating them alike is how the
notification command stayed broken for a year.

Three tiers, and nothing is promoted without a reason.

A fourth source now sits beside them: [docs/protocol/](protocol/README.md),
the protocol as the official Even app 1.6.5 implements it, read in its
decompiled code. It says what that app sends, not what the glasses accept,
so it informs these tiers without promoting anything in them. Where it
speaks to a line below, the line says so.

## Confirmed on these glasses

| | |
|---|---|
| `0x4B` notification header | Four bytes: command, notifyId, chunk count, chunk index. The three-byte shape inherited from the fork made the firmware read the count as the id and discard the notification without a sound. Fixed in v1.2.3-beta.6, and pinned by `test/protocol_routing_test.dart` |
| `0x4B` routing | Both temples. The circulating protocol document calls it a left-arm command; routing it that way is what made notifications never appear. The official app 1.6.5 sends it to the left temple only, with byte 1 at `0x00` and an acknowledgement per packet |
| `0xF5` sub-code `0x0F` | The charging case's level, 0x00 to 0x64 |
| `0x06` layout framing | Command, length as a little-endian short counting the header, sync id, then the payload. Every dashboard command this app sends is built this way and works |
| Text pagination | Five lines to a screen |

## Inherited, working, unexamined

Code that came from [AGiXT/mobile](https://github.com/AGiXT/mobile) and
[fahrplan](https://github.com/meyskens/fahrplan), does its job, and has never
been checked against anything.

| | |
|---|---|
| Screen-status byte | This app composes `0x20 \| 0x10` = 0x30. Two other implementations read the high nibble as the mode and the low one as the action, which would make it 0x31, or 0x71 for plain text rather than an Even AI answer. Text displays today either way. The official app 1.6.5 no longer sends `0x4E` at all, so it cannot settle this |
| Characters per line | **Disputed.** `lib/services/teleprompter_tracker.dart` says twenty-five was measured on hardware; openg1-sdk and g1bridge both compute forty from a 488 pixel column at font size 21. The pages go out through the same command, so both cannot be right. The official app uses no count at all: it wraps by measured width, 450 pixels at font size 20, for its teleprompter and its AI answers |
| `0x15` bitmap transfer | Chunks of 194 bytes to a fixed storage address, then end and CRC. Works; the address bytes have never been questioned |

## Reimplemented from other projects, never seen working

Written from what someone else established, tested as far as a test can
reach, and waiting for a face.

| | |
|---|---|
| Dashboard news pane | `0x06` sub-command `0x05`: display mode, pane, news mode, slot one to four, operation, then source and body as tagged fields. From `even-utils`. The official app 1.6.5 builds it the same way, with limits of 40 bytes for the source and 279 for the body |
| Dashboard map pane | `0x06` sub-command `0x07`: a one-bit image the size of the pane — 376×136 in dual mode, 296×136 in full — packed low bit first with no row padding, plus a 32×32 sprite with a position. From `even-utils`. Same display modes and framing in the official app 1.6.5 |
| `0x4C` | Should dismiss the banner `0x4B` put up. Never tried. The official app 1.6.5 sends five bytes: `4C` and the message id as a big-endian u32, to the left temple |
| `0xF5` sub-codes beyond the five we act on | Named from the community table, reported in Settings → Debug, acted on by nothing |

## How to settle any of it

Settings → Debug sends the same content several ways and shows the lens
mirror above, so the difference is visible rather than argued about:

- the same paragraph at twenty, twenty-five and forty characters a line
- the same page with status 0x30, 0x31 and 0x71
- `0x4C`, on a lens showing a notification
- a news card, and a calibration chart for the map pane

The chart is drawn to fail loudly: a missing edge means the pane is not the
size we think, a broken diagonal means the rows are in the wrong order, and
three pixels that jump to the right of an eight-pixel group mean the bit
order is reversed.

Findings are welcome as issues, and corrections to this file more so.
