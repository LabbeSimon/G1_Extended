# Teleprompter (official Even app 1.6.5)

Read line by line in the decompiled `Proto` (service/proto.dart), `Telepromt`
(service/telepromt.dart) and `LayoutConfigs` (page/teleprompter). Every fact
below is **[certain]** unless marked. Timeouts are the real values:
what a caller passes as an argument is a tagged small integer, half of the
immediate shown in the disassembly.

## Shared sequence counter

One app-wide counter `P` (a static in Proto) feeds byte 3 of every teleprompter
frame: 0x09 (all subs), 0x24 and 0x25. The value written is `P % 255`; `P` is
incremented after each frame is built, and the same frame (same `P`) goes to
both temples. `P` is reset to 0 once the last start packet has been accepted
by the right temple, so the frames that follow a successful start count again
from 0. Responses are matched by BleManager on side + first byte (0x09, 0x24,
0x25), not on `P`.

## 0x09 sub 0x01 - start (first screen)

```
09 LL LL P 01 T0 T1 N0 N1 CD MM PR  <UTF-8 text>  [00 x8 on the last packet]
```

| byte | value |
|---|---|
| 1-2 | total frame length, LE16 = 12 + text bytes (+8 when N == T) |
| 3 | P % 255 |
| 4 | 0x01 |
| 5-6 | T = number of packets of this screen, LE16 |
| 7-8 | N = index of this packet, 1-based, LE16 |
| 9 | `countdownSeconds + 1` (setting, default 0, so 0x01 without countdown) |
| 10 | `0x80 | mode`, mode = 0 AUTO (timed scroll), 1 MANUAL, 2 AI (voice follow); any other value is sent as 0 |
| 11 | progress 0..100 at start (same formula as below) |

- Last packet (N == T) gets 8 zero bytes appended; they are counted in the length.
- Sent to L (timeout 3000 ms) and, only if L acknowledged, to R (3000 ms).
- Ack: first byte 0x09, byte 4 == 0x01, byte 9 == 0x00. Any other byte 9 is a failure.
- On success of the last packet (R accepted it): the app empties its update
  queue, sets its "teleprompter started" flag and resets `P` to 0.
- The app retries the whole start up to 3 times; mode 2 (AI) also clears the pending update queue first.

## 0x09 sub 0x03 / 0x07 - screen update

```
09 LL LL P SS T0 T1 N0 N1 PR 00 00  <UTF-8 text>  [00 x8 on the last packet]
```

- SS = 0x07 when the update is a one-row animated scroll (`updateOneRow`) AND
  the firmware supports it (device firmware version > 1.2.10), else 0x03.
- Byte 9 = progress 0..100; bytes 10-11 = 0 in manual/auto mode.
- L (timeout 500 ms) then R (1000 ms). Ack: byte 4 in {0x03, 0x07}, byte 9 == 0x00.
- Updates go through a single-flight queue; when a new first packet (N < T)
  is enqueued, a pending stale update is dropped.

## 0x09 sub 0x03 / 0x07 - AI (voice-follow) screen

Same as the update, except bytes 10-11 = `position`, LE16: the character offset
of the matched spoken word in the screen text (indent spaces included).
L timeout 300 ms, R 1000 ms.

## Screen content

- The script is pre-wrapped into a list of display lines by the phone.
- A screen is the 5 lines starting at the current top line. Each line is sent
  followed by `\n`.
- Fewer than 4 lines left: one packet (T = 1, N = 1) with all of them.
  Otherwise two packets: N = 1 carries lines 0-2, N = 2 carries lines 3-4.
- Before sending, every non-empty line is prefixed with an indent of spaces
  computed from the "vision width" setting (0 at the default 472 px width).
- Progress: AUTO/MANUAL: `lines <= 5 ? 100 : 100 * top / (lines - 5)`;
  AI: `lines <= 2 ? 100 : 100 * top / (lines - 2)` (integer division).

## 0x09 sub 0x02 - run dot (AI mode)

`09 10 00 P 02 X Ylo Yhi` + 8 zero bytes (16 bytes). X = progress byte,
Y = LE16 position. Only sent once a start has succeeded (the flag set at the
end of the start sequence); before that the app skips it.

## 0x09 sub 0x05 - stop

`09 06 00 P 05 01`, L then R (1000 ms each).

## 0x24 - pause / resume

`24 12 00 P 06 F` + 8 zero bytes + `S` as LE32 (18 bytes). F = pause flag
(1 paused, 0 running), S = seconds elapsed. L (500 ms) then R (1000 ms).

## 0x25 sub 0x04 - heartbeat

`25 06 00 P 04 P` (P twice), right temple only, timeout 2000 ms.
Sent every 2 s while the teleprompter runs (1 s timer, every other tick).
After 10 consecutive failed heartbeats the app gives up: it stops its timers
and leaves the teleprompter screen.

## Settings object (LayoutConfigs, JSON keys)

isAzure, language, isUndisturbedMode, telepromtMode (AI 0 / MANUAL 1 / AUTO 2
in the app enum - NOT the wire value), speed (double), isBluetoothControl,
countdownSeconds (int), visionWidth (int, presets 192..472 step 28, default
472), isLoop. Status enum: AUTO_WORKING 0, MANUAL_WORKING 1, AI_WORKING 2,
NOT_WORKING 3.
