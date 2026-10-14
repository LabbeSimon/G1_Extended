# Settings and device commands (official Even app 1.6.5)

Every settings and device command of the official app's protocol class that the other files do not cover: [teleprompter](teleprompter.md); [Even AI, transcription, translation, microphone, 0x18/0x50/0x51](even-ai-transcribe-translate.md); [notes, notifications, allowlist, dashboard, navigation](notes-notifications-dashboard-navigation.md); [transport, keep-alive, firmware, fonts, 0xF5 events](transport.md). "both (fire-and-forget)" = `sendData` without side: the frame is written to both arms, no reply awaited. Details and certainty marks follow the table.

| Opcode | Sub-cmd | Name | Side / timing | Length | Response |
|---|---|---|---|---|---|
| 0x01 | - | setBrightness | R, fire-and-forget | 3 | none awaited |
| 0x03 | - | setDisplayMode (silent mode) | L+R in parallel, 300 ms, 3 retries | 3 | `data[1] == 0xC9` on both |
| 0x08 | 0x03 | setHeadUpType | both (fire-and-forget) | 6 | none awaited |
| 0x08 | 0x04 | getHeadUpType | R, 500 ms | 6 | `data[5]`: 0 = dashboard, else none |
| 0x0B | - | setEyeGlassAngle | R, fire-and-forget | 3 | none awaited |
| 0x10 | 0x01 | setEyeGlassDefaultZeroAngle | default side, 4 x 200 ms | 5 | `data[5] == 0xC9` |
| 0x10 | 0x02 | startEyeGlassDiyZeroAngle | default side, 4 x 200 ms | 7 | `data[5] == 0xC9` |
| 0x13 | - | setLegSn (debug) | caller's side, fire-and-forget | 1 + SN (max 200) | none awaited |
| 0x14 | - | setAncsStatus | L, 500 ms | 2 | not inspected |
| 0x17 | - | upgradeMode | L, then R if L ok (250 ms each) | 1 | `data[1] == 0xC9` |
| 0x19 | - | setEsbAddr (debug) | L, then R if L ok (250 ms each) | 3 | `data[1] == 0xC9` |
| 0x1F | - | setOnboardingOrder | L, then R if L ok (1000 ms each) | 3 | `[0x1F, step, 0xC9]` |
| 0x23 0x6C | "#l" / "#l1" | debugLog | both (fire-and-forget) | 2 / 3 | none (log arrives as 0xF4) |
| 0x23 0x72 | "#r" | restart | caller's side or both, fire-and-forget | 2 | none (arm reboots) |
| 0x23 0x74 | "#t" | glassDebugInfo | caller's side, 500 ms, next frame | 2 | ASCII build string, no header |
| 0x26 | 0x01 | deviceReset | L+R in parallel, 300 ms, 3 retries | 5 | `data[5] == 0xC9` on both |
| 0x26 | 0x02 | setDisplaySetting (height/depth) | default side, 1000 ms | 8 | not inspected |
| 0x26 | 0x04 | setBrightnessLUM | caller's side, 4 x 200 ms | 6 | `data[5] == 0xC9` |
| 0x26 | 0x05 | setDoubleTapFunction | both (fire-and-forget) | 6 | none awaited |
| 0x26 | 0x06 | glassLumSettingEnterOrExit | L then R, 3 s, 5 retries | 6 | matched on sync id |
| 0x26 | 0x06 0x02 | setGlassLum | one arm (caller), 200 ms | 7 | `data[5] == 0xC9` |
| 0x26 | 0x07 | setPressHoldMode | R, 2 s | 6 | `data[5] == 0xC9` |
| 0x26 | 0x08 | updateVoiceWakeupSwitchStatus | R, 1000 ms, 3 attempts | 6 | `data[4] == 0x08`, `data[5] == 0xC9` |
| 0x27 | - | setConfigWearCheck | both (fire-and-forget) | 2 | none awaited |
| 0x29 | - | getBrightness | R, 500 ms | 1 | `data[2]` level, `data[3]` auto |
| 0x2A | - | getEIS | R, 500 ms | 1 | `data[2]` |
| 0x2B | - | getGlassMode | default or caller's side, 4 x 500 ms | 1 | `data[2]` 0x0C silent / 0x0A normal, `data[3]` |
| 0x2C | 0x01 (0x02 iOS?) | deviceInfo | each arm, 6 x 500 ms | 2 | battery, voltage, firmware versions (>= 20 bytes) |
| 0x32 | - | getEyeGlassAngle | R, 4 x 1500 ms, run twice | 1 | `data[2]` angle, `data[3]` level |
| 0x34 | - | getLegSn | caller's side, 500 ms | 1 | bytes 2..17 = serial string |
| 0x37 | - | getUpTime | caller's side, 500 ms | 1 | u32 LE at bytes 2..5 (seconds) |
| 0x38 | - | getAncsStatus | L, 500 ms | 1 | `data[2] == 0x01` = enabled |
| 0x39 | 0x01 | fetchDeviceRunningStatus | L then R, 500 ms each | 5 | `data[5]` = running feature |
| 0x3A | - | getConfigWearCheck | default side, 500 ms | 1 | `data[2]` 0x01/0xFF = on |
| 0x3B | - | getDisplaySetting | R, 500 ms | 1 | `data[2]` height, `data[3]` depth |
| 0x3C | - | getDirectSettings | L, 500 ms | 1 | `data[2]` enable, `data[3]` stay time |
| 0x3D | 0x01 | appSetting (language) | L then R, 2 s, 10 retries | 6 | echo, `data[5] == lang` |
| 0x3E | - | getG1Data (usage statistics) | R, 500 ms | 1 | statistics block, little-endian |
| 0x3F | 0x05 | getDoubleTapFunction | R, 500 ms | 2 | `data[2] == 0xC9`, `data[3]` function |
| 0x3F | 0x06 | getGlassLum | one arm (caller), 2 s | 2 | `data[2] == 0xC9`, `data[3]` luminance |
| 0x3F | 0x07 | fetchPressHoldMode | R, 2 s | 2 | `data[2] == 0xC9`, `data[3]` mode |
| 0x47 | - | sendUnpair | caller's side, 500 ms | 1 | not inspected |
| 0x4F | - | setDirectPush | L, then R if L ok (1500 ms each) | 3 | `data[1] == 0xC9`, `data[2] == enable` |
| - | - | disconnect | local only, no frame | 0 | - |

Opcodes listed by the reference document but never sent by this class: 0x2D (MAC), 0x2E (whitelist read), 0x33, 0x35, 0x36. "0x2C 0x02" in the document is most likely the iOS form of the same 0x2C request (the second byte is a platform flag, not a sub-command).

---

## Details

Marks: [certain] = seen directly in the official app; [probable] = inferred.

## Conventions used by the app

- Every frame is a plain byte array sent on the UART-style characteristic. Several settings use the "0x26 family" frame `[0x26, len, 0x00, seq, sub, params...]` (len = total frame length, here 6 or 7).
- `BleManager.request(frame, {lr, timeoutMs = 500, useNext = false})`: sends the frame to one arm and waits for a notification whose first byte equals the frame first byte and that comes from the same arm. Default timeout 500 ms. The reply wait has no ceiling of its own; the 2 s limit in the app applies to the native write call (see [transport.md](transport.md), section 6). A timeout returns a pseudo-reply flagged "timeout". [certain]
- `BleManager.requestRetry(frame, {lr, retry = 3, timeoutMs = 200})`: calls `request` up to retry + 1 times (default 4 attempts of 200 ms each, back to back, no pause); stops early as soon as one arm is disconnected. [certain]
- `lr` omitted in `request`: R when R is connected (or both are), otherwise L. [certain]
- `BleManager.sendData(frame, {lr})` is fire-and-forget (no reply awaited). With an explicit `lr` it writes that arm only. Without `lr` it writes BOTH arms one after the other (normally R first, then L); if the first write is not acknowledged at link level the app waits 100 ms before writing the other arm. The order is chosen from a state flag of the left-arm connection object. [certain for "both arms" and the 100 ms; order details probable]
- `BleManager.sendBoth(frame, {retry})`: `requestRetry` on L with 250 ms per attempt; R is written (same 250 ms per attempt) only if L answered with `data[1] == 0xC9`. Returns true only if both answered. [certain]
- `BleService.sendOneSide / sendLeftSide / sendRightSide(frame, matcher, {timeout = 200 ms})`: one arm, waits for the first notification accepted by the caller-supplied matcher. The whole frame is written; only its first 20 bytes go into the app's log line. [certain]
- `BleService.sendBothSide(frame, matcher, validator, {isInOrder = true, retryCount = 0, timeout = 300 ms})`: with isInOrder = true the arms are handled strictly in sequence: L, wait for its reply, check it with the validator, then R, wait and check. With isInOrder = false L and R are written in parallel and both replies awaited. If the result is false and retryCount > 0, the app waits 20 ms and redoes the whole exchange with retryCount - 1 (so 20 ms is the pause between two retries, not between L and R). [certain]
- Typical response: `data[0]` = echoed opcode, `data[1]` (or `data[2]` for some commands) = 0xC9 success / 0xCA failure. [certain]
- Sequence counters (8-bit, incremented after use, wrapping after 255): counter A (used by `_getSyncId`), counter B (setBrightnessLUM, setDisplaySetting), counter C (setDoubleTapFunction, setHeadUpType, getHeadUpType, `_sendEnableIntoFunction`). They are independent. [certain]

## 0x2B - getGlassMode
- Frame: `[0x2B]` (1 byte). `getGlassMode({lr, timeoutMs = 500})` uses `requestRetry` with the default retry count: up to 4 attempts of 500 ms. Side: default (R preferred) during onboarding; the home page queries L and R separately; one caller passes 1000 ms per attempt. [certain]
- Response: `data[2]` = first value, `data[3]` = second value; returned as a pair (int, int). On no response the app uses the default pair (0x0A, 0x07). [certain for offsets, meaning unknown]
- Semantics of the two values: not decoded (probably glasses mode / sub mode). [probable]

## 0x3A - getConfigWearCheck (wear detection state)
- Side: default (R preferred). Frame: `[0x3A]` (1 byte), plain `request` (500 ms default). [certain]
- Response: `data[2]`: 0x01 or 0xFF = enabled (true); anything else = disabled. No response => true. [certain]

## 0x27 - setConfigWearCheck
- Frame (2 bytes): `[0x27, enable]`, enable = 0x01 on, 0x00 off. [certain]
- Side: no side given, so `sendData` writes BOTH arms (R then L in the usual case), fire-and-forget: no reply is awaited. Called from the wear-detection settings page. [certain]

## 0x2A - getEIS
- Side: R. Frame: `[0x2A]`. request, 500 ms (default). [certain]
- Response: `data[2]` returned as an int (EIS value, meaning unknown); 0 on timeout. [certain offset, semantics probable: electronic image stabilisation / eye-info state]

## 0x26 sub 0x05 - setDoubleTapFunction
- Side: no side given, so `sendData` writes BOTH arms (R then L in the usual case), fire-and-forget. [certain]
- Frame (6 bytes): `[0x26, 0x06, 0x00, seq, 0x05, function]`. seq = counter C value (0..255). [certain]
- function (wire value for the app enum DoubleTapFunction): 0x00 = None (close feature), 0x01 = Navigate, 0x02 = Translate, 0x03 = Teleprompt, 0x04 = Dashboard, 0x05 = Transcribe. Note the app enum order is Dashboard 0, Navigate 1, Translate 2, Teleprompt 3, Transcribe 4, None 5, so Dashboard / Transcribe / None are remapped on the wire. [certain]

## 0x3F - getDoubleTapFunction
- Side: R. Frame: `[0x3F, 0x05]`. request, 500 ms (default). [certain for bytes; the 0x05 is the same sub-id as in the set command, probable]
- Response: valid if `data[2] == 0xC9`; `data[3]` = function using the same wire table as the set command (0 or unknown = None, 1 Navigate, 2 Translate, 3 Teleprompt, 4 Dashboard, 5 Transcribe). No valid reply => None. [certain]

## 0x08 - setHeadUpType
- Side: no side given, so `sendData` writes BOTH arms, fire-and-forget. [certain]
- Frame (6 bytes): `[0x08, 0x06, 0x00, 0x00, 0x03, value]`; value = 0x00 -> Dashboard shown on head-up, 0x02 -> None (feature off). The seq byte is always 0 here although counter C is still incremented. [certain]
- App meaning: the app's parameter is a bool "dashboard selected"; true => 0x00, false => 0x02. [certain]

## 0x08 sub 0x04 - getHeadUpType
- Side: R. Frame (6 bytes): `[0x08, 0x06, 0x00, seq, 0x04, 0x00]`, seq = counter C. request, 500 ms (default). [certain]
- Response: `data[5]`: 0 = Dashboard, non-zero = None. Timeout => Dashboard. [certain]

## 0x0B - setEyeGlassAngle (head-up angle)
- Side: R, fire-and-forget `sendData`. Frame (3 bytes): `[0x0B, angle, level]`. angle is clamped by the app to 0..60 (degrees). level is the second argument, passed through unchanged (meaning of "level" probable: the angle preset / calibration level). [certain for bytes]

## 0x32 - getEyeGlassAngle
- Side: R. Frame: `[0x32]` (1 byte). `requestRetry` with 1500 ms per attempt and the default retry count (up to 4 attempts); if that whole call times out the app runs a second identical `requestRetry`. [certain]
- Response: `data[2]` = angle, `data[3]` = level (same two quantities as in 0x0B). If both attempts time out the app falls back to the angle stored locally and level 0. [certain]

## 0x10 family - eye-glass zero-angle calibration
Both use `requestRetry` with its defaults on the default side (R preferred): up to 4 attempts of 200 ms. Success = `data[5] == 0xC9`. [certain]
- Sub 0x01, setEyeGlassDefaultZeroAngle: 5 bytes `[0x10, 0x05, 0x00, seq, 0x01]`. seq is a caller-supplied counter, forced to 0 if above 255. Asks the glasses to reset the zero angle to the factory default. [certain bytes, semantics probable]
- Sub 0x02, startEyeGlassDiyZeroAngle(isEnd, isSuccess): 7 bytes `[0x10, 0x07, 0x00, seq, 0x02, A, B]`. A = 0x01 while the DIY procedure is running (isEnd false) and 0x00 when the app ends it (isEnd true); B = 0x01 if the app reports success, 0x00 otherwise (both flags default to false). [certain]

## 0x26 sub 0x06 - glassLumSettingEnterOrExit
- Side: both arms, `sendBothSide` in order (L, then R), 3 s timeout per arm, retryCount 5 (20 ms pause between retries). [certain]
- Frame (6 bytes): `[0x26, 0x06, 0x00, syncId, 0x06, enter]`; syncId from counter A (`_getSyncId`); enter = 0x01 to enter the luminance-setting mode, 0x00 to leave it. Reply is matched on the sync id. [certain]

## 0x26 sub 0x06/0x02 - setGlassLum (per-arm luminance / calibration value)
- Side: one arm chosen by the caller (isLeft true => L, else R), `sendOneSide`, default timeout 200 ms, no retry. [certain]
- Frame (7 bytes): `[0x26, 0x07, 0x00, syncId, 0x06, 0x02, lum]`. lum = low 8 bits of the integer supplied by the app (no clamping). Success = reply `data[5] == 0xC9`. [certain]

## 0x3F 0x06 - getGlassLum
- Side: one arm chosen by caller (isLeft true => L, else R). Frame: `[0x3F, 0x06]`. Timeout 2 s. [certain]
- Reply matcher: `data[0] == 0x3F` and `data[1] == 0x06`. Valid if `data[2] == 0xC9`; `data[3]` = luminance value. Otherwise null. [certain]

## 0x3F 0x07 - fetchPressHoldMode
- Side: R. Frame: `[0x3F, 0x07]`. Timeout 2 s. Valid if `data[2] == 0xC9`; `data[3]`: 0x00 = Even AI (long press), 0x01 = Quick Note; anything else => unknown (null). [certain]

## 0x26 sub 0x07 - setPressHoldMode
- Side: R, `sendOneSide`, 2 s timeout. Frame (6 bytes): `[0x26, 0x06, 0x00, syncId, 0x07, mode]`. mode: 0x01 = Quick Note (app enum index 0), 0x00 = Even AI (index 1). Success = reply `data[5] == 0xC9`. [certain]
- Note: opcode family `0x3F <subject>` is a "get setting" family: 0x05 double tap, 0x06 glass luminance, 0x07 press-and-hold; and `0x26 <len> 0 seq <subject> ...` is the matching "set" family (subjects 0x05, 0x06, 0x07 plus 0x02 display and 0x04 brightness LUM). [certain]

## 0x01 - setBrightness
- Side: R only (`sendData`, no reply awaited by the app). Frame (3 bytes): `[0x01, level, auto]`. level = app value clamped to 0..42 (0x00-0x2A); auto = 0x01 auto-brightness on, 0x00 off. Agrees with the reference doc. [certain]

## 0x29 - getBrightness
- Side: R. Frame: `[0x29]`. request, 500 ms (default). Response: `data[2]` = level (0..0x2A), `data[3] == 0x01` means auto-brightness enabled. Timeout => (0, false). [certain]

## 0x37 - getUpTime
- Side: given by the caller (`getUpTime(lr)`). Frame: `[0x37]`. request, 500 ms (default). Response: 32-bit little-endian integer read from `data[2..5]` (seconds since boot, probable unit); 0 on timeout. The reference document's sample (`37 49 1a 00 00`) places the value one byte earlier; the app reads bytes 2 to 5 (see [transport.md](transport.md), section 14). [certain for the offsets the app reads]

## 0x03 - setDisplayMode (silent / disturb mode)
- Side: both arms, `sendBothSide` in parallel (isInOrder = false), 300 ms timeout (default), retryCount 3 (20 ms pause between retries). Reply matcher: `data[0] == 0x03` and reply length >= 2; success when `data[1] == 0xC9` on both arms. [certain]
- Frame (3 bytes): `[0x03, mode, extra]`. mode: 0x0C = silent mode on, 0x0A = off (0x0B also accepted by the app as a valid value; the app tests 0x0A..0x0C). extra is a second argument: the app passes 0x00 when entering silent mode (mode 0x0C) and 0x01 with mode 0x0A (OTA / firmware-version screens). The reference doc shows only 2 bytes; the app sends 3. [certain bytes; extra semantics unknown]

## 0x2B - getGlassMode (update)
- Per the reference doc and the values above: `data[2] == 0x0C` means silent mode enabled, 0x0A disabled; `data[3]` is an extra byte (doc samples 0x06 / 0x08). Default on timeout (0x0A, 0x07). [probable]

## 0x26 sub 0x02 - setDisplaySetting (display height / depth)
- Side: one arm, default (R preferred), `request` with 1000 ms timeout. [certain]
- Frame (8 bytes): `[0x26, 0x08, 0x00, seq, 0x02, preview, height, depth]`; seq = counter B mod 255, incremented after each call. preview (the app calls it isEnable) = 0x01 shows the live preview, 0x00 commits. height: app value clamped to 0..8 (negative => 0). depth: negative => 1, 0 passes through as 0 (unclamped), 1..9 unchanged, > 9 => 9. The doc samples show both arms, the app uses only one. [certain bytes]
- Reply: `[0x26, 0x06, 0x00, seq, 0x02, 0xC9/0xCA]` (per doc). The app does not inspect it. [probable]

## 0x3B - getDisplaySetting
- Side: R. Frame: `[0x3B]`. request, 500 ms (default). [certain]
- Response: `data[2]` = height raw (0..8), `data[3]` = depth raw (1..9). The app returns the pair (depth_or_2, 8 - height): depth is replaced with 2 if the byte is 0; the first-returned value is data[3] and the second is 8 - data[2]. Timeout => (3, 2). [certain offsets; interpretation probable]

## 0x4F - setDirectPush (notification direct push)
- Sides: L first (`request`, 1500 ms), then the same frame to R (`request`, 1500 ms) only if L's reply was valid. Frame (3 bytes): `[0x4F, enable, stayTime]`; enable 0x01/0x00, stayTime in seconds (app default 10). [certain bytes and sides; stayTime unit probable]
- Valid reply (checked on each arm): `data[0] == 0x4F`, length > 2, `data[2]` equals the enable byte sent and `data[1] == 0xC9`. Returns true only if both arms are valid. [certain] The app also stores the settings locally. [probable]

## 0x3C - getDirectSettings
- Side: L. Frame: `[0x3C]`. request, 500 ms (default). Response: if `data[1] != 0xCA`: enabled = (`data[2] == 0x01`), stayTime = `data[3]` (10 if 0). Timeout or 0xCA => (false, 10). [certain] (The reference doc lists 0x3C only as "message mode"; it is the Direct Push readback.)

## 0x26 sub 0x04 - setBrightnessLUM
- Side: chosen by caller (`lr`), `requestRetry` with defaults (up to 4 attempts of 200 ms). Frame (6 bytes): `[0x26, 0x06, 0x00, seq, 0x04, lum]`; seq = counter B mod 255; lum = raw luminance byte given by the caller (range not clamped; probable 0..255). Success = reply `data[5] == 0xC9`. [certain]

## 0x2C - deviceInfo (battery / firmware version), sub 0x01
- Sides: each arm is queried separately with an explicit side (`updateDeviceInfo("L")` and `updateDeviceInfo("R")`). [certain]
- Frame (2 bytes): `[0x2C, platform]`. platform = 0x01 in the Android build (0x02 is very likely what the iOS build sends). [certain for the Android value; iOS value probable]
- Transport: `requestRetry` with retry = 5 (up to 6 attempts) and 500 ms per attempt (default when the caller passes nothing; `updateDeviceInfo` also passes 500 ms). [certain]
- Reply: `[0x2C, status?, b2, b3, ..., b12, ...]`. The parser reads bytes 2 to 12 and also range-checks indexes 13 to 19, so a reply shorter than 20 bytes makes the app throw (caught, logged "updateDeviceInfo error"). Byte 1 is not checked. [certain]
- Decoding (field order of the app object `DeviceInfo`), all unsigned bytes: [certain for the arithmetic, names probable unless stated]
  - `b2`: battery percentage of the answering arm (0..100). [probable, matches this app's battery captures where both arms read 100]
  - `b3`: second percentage-like byte (0x64 on R, 0x00 on L in the reference-doc sample). Not used by the app. [meaning unknown; case battery is a hypothesis]
  - `b4`: voltage, decoded as `(b4 + 200) / 100` volts (range 2.00 to 4.55 V; doc samples 0xEF -> 4.39 V on a full arm, 0xE6 -> 4.30 V). [formula certain, "voltage" probable]
  - `b5`: signed quantity stored as `b5 - 128` (doc samples 0x80 -> 0 on a full arm, 0x5D -> -35). Probably the battery current (negative = discharging). [formula certain, meaning probable]
  - `b6`: one byte stored as is (doc samples 0x19 = 25, 0x24 = 36). Probably the temperature in degrees C. [meaning probable]
  - `b7.b8.b9`: firmware version (major.minor.patch) reported by the R arm. [certain]
  - `b10.b11.b12`: firmware version reported by the L arm. [certain]
  - The displayed firmware version is `b7.b8.b9` when the reply came from R ("master") and `b10.b11.b12` when it came from L. "0.0.0" is treated as "version not known" (`versionCorrect` is false). [certain]
- Only the version string is used by the app UI (settings, firmware page, feature gating such as heartbeat support). The battery shown in the UI comes from another path (glass state events), not from this reply. [certain]
- Alignment note: the reference-doc samples `L 00 e6 5d 24 00 00 00 01 04 05 ...` and `R 64 ef 80 19 01 04 05 01 04 05 ...` start at byte 3, not byte 2: with that alignment R gives 1.4.5 at b7..b9 and L gives 1.4.5 at b10..b12, which matches the firmware version of that era. [probable]

## 0x23 0x72 ("#r") - restart
- Frame (2 bytes): the ASCII string "#r" = `[0x23, 0x72]`. [certain]
- Side: the caller may pass a side; when none is given `sendData` writes both arms (see conventions). Fire-and-forget: no reply is awaited (the arm reboots). The first argument is only a log label ("from"). [certain]
- Used by the DFU flow, the link monitor, the quick-note service, the device page and the debug page. [certain]

## 0x17 - upgradeMode (enter firmware-upgrade mode)
- Frame (1 byte): `[0x17]`. [certain]
- Side: both arms through `sendBoth`: L first (one attempt, 250 ms), then R only if L replied `[0x17, 0xC9, ...]`. Returns true when both acknowledged. Called by the DFU service. [certain]

## 0x23 0x74 ("#t") - glassDebugInfo (firmware build string)
- Frame (2 bytes): ASCII "#t" = `[0x23, 0x74]`. Side given by the caller. [certain]
- Sent with `request(..., useNext: true)`: the reply is not matched on its first byte; the next inbound frame from that arm (other than the special ones) is taken as the answer, because the reply has no command header. Timeout 500 ms (default). [certain]
- Decoding: trailing 0x00 bytes are stripped and the remaining bytes (from byte 0) are UTF-8 decoded into a string (e.g. "net build time: ..., app build time ..., ver 1.4.5, JBD DeviceID 4010" per the reference doc). Used by the link monitor. [certain]

## 0x3E - getG1Data (usage statistics, "buried point")
- Frame (1 byte): `[0x3E]`. Side: R. `request`, 500 ms (default). On timeout the result is null. [certain]
- Reply: bytes 0-1 (`0x3E`, status) are skipped; the payload from byte 2 is parsed little-endian as follows. [certain]
  - u32 `sys_id`
  - u32 `wear_sum_time`, u32 `wear_count`
  - u32 `dashboard_sum_time`, u32 `dashboard_count`
  - i8 `day_sum_num` (number of daily records N), i8 `day_index`, then 2 bytes ignored (header = 24 bytes)
  - `wear_info`: N records of 12 bytes
  - `dashboard_info`: N records of 12 bytes
  - only if at least 92 bytes remain (= 8 + 7 x 12): u32 `notification_sum_time`, u32 `notification_count`, then `notification_info`: N records of 12 bytes. Older firmware simply stops after dashboard_info. [certain]
- Daily record (12 bytes, little-endian): u16 `year`, i8 `month`, i8 `day`, u32 `accum_time`, u32 `accum_count`. [certain]
- Field names are the JSON keys the app uses (it uploads this object as telemetry). Time unit not stated in the app (probably seconds). With N = 7 the reply is 2 + 24 + 168 = 194 bytes without the notification block. [names certain, unit probable]

## 0x3D sub 0x01 - appSetting (glasses UI language)
- Called when the user changes the app language (the glasses follow the app language). [certain]
- Frame (6 bytes): `[0x3D, 0x06, 0x00, seq, 0x01, lang]`. seq = a dedicated 8-bit counter taken modulo 255 and incremented after use (reset when it reaches 255). [certain]
- lang (wire value; app enum `LanguageType` index in brackets): 0x01 Chinese [1], 0x02 English [0], 0x03 Japanese [7], 0x04 Korean [8], 0x05 French [4], 0x06 German [2], 0x07 Spanish [3], 0x08 Russian [6], 0x09 Dutch [9], 0x0A Norwegian [10], 0x0B Danish [11], 0x0C Swedish [12], 0x0D Finnish [13], 0x0E Italian [5], 0x0F Polish [14], 0x10 Czech [15], 0x11 Portuguese [16], 0x12 Turkish [17]. [certain]
- Transport: `sendBothSide` in order (L, then R), 2 s timeout per arm, retryCount 10 (20 ms pause between retries). [certain]
- Reply accepted when `data[0] == 0x3D`, length >= 6, `data[3] == seq` and `data[4] == 0x01`; success when `data[5] == lang` (the glasses echo the frame). [certain]

## 0x39 sub 0x01 - fetchDeviceRunningStatus (what each arm is currently showing)
- Frame (5 bytes): `[0x39, 0x05, 0x00, seq, 0x01]`; seq = counter A (the shared sync-id counter, value modulo 255). The counter is advanced once when the frame is built and once more after each arm's reply (so +3 per call). [certain]
- Sides: L then R, sequentially (R is asked only after L answered or timed out), same frame on both, plain `request` with the default 500 ms timeout each. Result = pair (L status, R status). Used by the feature coordinator and Even AI before starting a feature. [certain]
- Reply: `[0x39, 0x05, 0x00, seq, 0x01, status]` (reference-doc capture: `39 05 00 5f 01 00`). Shorter than 6 bytes or timeout => unknown (null). [certain]
- status (byte 5): 0x00 none (idle), 0x04 ANCS, 0x05 notification, 0x06 dashboard, 0x07 disturb (silent mode), 0x09 teleprompter ("prompt"), 0x0A navigation, 0x0B translation, 0x0C quick note, 0xFF error; any other value (0x01-0x03, 0x08, 0x0D-0xFE) => unknown (null). [certain]

## 0x26 sub 0x08 - updateVoiceWakeupSwitchStatus (voice wake-up for Even AI)
- Frame (6 bytes): `[0x26, 0x06, 0x00, seq, 0x08, flag]`. Bytes 1-2 are the frame length written as a 16-bit little-endian value (6, 0). seq = a dedicated counter (counter E) taken modulo 255, incremented after every attempt. [certain]
- flag = 0x00 when `isOn` is true and 0x01 when it is false (the name comes from the app's log line "---isOn--"). The inverted polarity is what the app does; it was not checked against a device. [certain in the app]
- Side: R only, `request` with a 1000 ms timeout. Up to 3 attempts, with a 100 ms pause after a failed attempt. A new seq is used for each attempt. [certain]
- Success: reply `data[0] == 0x26`, length > 5, `data[4] == 0x08` and `data[5] == 0xC9`. [certain]

## disconnect (no BLE frame)
- `Proto.disconnect(lr)` sends nothing to the glasses. It stores `allowAutoConnect = false`, forgets the saved device of that side and asks the native layer to drop the GATT link of arm `lr`. Listed here because it lives in the protocol class. [certain]

## 0x1F - setOnboardingOrder (onboarding step shown on the glasses)
- Frame (3 bytes): `[0x1F, step, seq]`. step = 1..0x12; the app refuses anything else (returns false without sending). seq = a dedicated onboarding counter (`_onboardingSyncID`) taken modulo 255, incremented after each call. [certain]
- Steps: the onboarding pages send 1..13 as the user advances; step 0x12 (18) is sent by `onboardingHeartBeat`, driven by a 2 s periodic timer while onboarding is running. Meaning of each page number not mapped. [values certain; 2 s timer probable]
- Sides: L first (`request`, 1000 ms); R is sent the same frame only if L replied correctly; R timeout 1000 ms. [certain]
- Success (checked on both arms): `data[0] == 0x1F`, `data[1] == step`, `data[2] == 0xC9`. Any mismatch or timeout => false. [certain]

## 0x14 - setAncsStatus (Apple ANCS notification source on/off)
- Frame (2 bytes): `[0x14, enable]`, enable = 0x01 on, 0x00 off. Side: L, `request` with the default 500 ms; the reply is awaited but not inspected. [certain]
- Called from the notification debug page and from getAncsStatus (below). ANCS is the iOS notification service, so this matters for iPhone pairing. [certain call sites; purpose probable]

## 0x38 - getAncsStatus
- Frame (1 byte): `[0x38]`. Side: L, `request`, 500 ms (errors are turned into a timeout). [certain]
- Reply: timeout or empty => false; `data[1] == 0xCA` => false; `data[2] == 0x01` => true (ANCS enabled). Any other `data[2]` => the app immediately sends `[0x14, 0x00]` (setAncsStatus off) and returns false. [certain]

## 0x19 - setEsbAddr (inter-arm ESB radio link parameters, debug)
- Frame (3 bytes): `[0x19, a, b]`, two caller-supplied bytes (the debug page passes the ESB address/channel values). Both arms through `sendBoth` (L, 250 ms; then R only if L replied `data[1] == 0xC9`). Only called from the factory/debug page. [bytes and transport certain; meaning of a/b probable: ESB = Nordic Enhanced ShockBurst link between the two arms]

## 0x13 - setLegSn (write arm serial number, factory/debug)
- Frame: `[0x13] + UTF-8(sn)`, truncated to 200 bytes in total. Side given by the caller; fire-and-forget `sendData` (no reply awaited). Only called from the debug page. [certain]

## 0x34 - getLegSn (read arm serial number)
- Frame (1 byte): `[0x34]`. Side given by the caller, `request`, 500 ms. [certain]
- Reply: bytes 2..17 (16 bytes) are turned into a string, one character per byte. Bytes 0-1 (`0x34`, status) are skipped; no status check. [certain]

## 0x47 - sendUnpair
- Frame (1 byte): `[0x47]`. Side given by the caller, `request`, 500 ms; the reply is not inspected. Used by "About my device" (unpair/forget glasses) and by the debug page, followed by a local `disconnect`. [certain frame; the follow-up probable]

## 0x26 sub 0x01 - deviceReset (reset the glasses settings, from the "Reset" settings page)
- Frame (5 bytes): `[0x26, 0x05, 0x00, syncId, 0x01]`; syncId = counter A (`_getSyncId`, 0..255). [certain]
- Sides: `sendBothSide` with isInOrder = false (L and R written in parallel), 300 ms timeout (default), retryCount 3 (20 ms pause between retries). [certain]
- Reply accepted when `data[0] == 0x26`, length >= 6, `data[3] == syncId` and `data[4] == 0x01`; success when `data[5] == 0xC9` on both arms. [certain]
- What exactly is reset (factory reset vs user settings) is not visible from the app. [unknown]

## 0x23 0x6C ("#l" / "#l1") - debugLog (glasses log switch)
- Frames: `debugLog(true)` sends ASCII "#l" = `[0x23, 0x6C]`; `debugLog(false)` sends "#l1" = `[0x23, 0x6C, 0x31]`. [certain]
- Side: none given, so both arms (`sendData`), fire-and-forget. [certain]
- Triggered by the support log-upload channel (server message field "IsOpenGlassLog": true -> "#l", false -> "#l1") and by the floating debug panel. Inbound 0xF4 frames are the glasses' debug log (see [transport.md](transport.md)). That "#l" switches the log on and "#l1" back off is inferred from the key name. [mapping certain; on/off meaning probable]

## lR() helper (no frame)
- Default side used by several commands: "R" when both arms are connected, "R" when only R is connected, otherwise "L". [certain]
