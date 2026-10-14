# Transport (official Even app 1.6.5)

Scope: scan, connection, framing, request/response matching, inbound events, audio, heartbeat, DFU, images, hosts.
Per-command payloads are in the other files of this folder.
Tags: **[certain]** = read directly in the decompiled code; **[probable]** = inferred.
Dart small ints inside lists are Smi-tagged in the dump (real value = shown/2); every value below was de-tagged.

## 1. Architecture of the bridge

- **[certain]** Dart talks to native Android code through MethodChannel `method.bluetooth` (methods: scan, scanStop, connect, disconnect, send, mtu, createBound, unpair, bondedDevices, refresh, setMicModel, lc3ToPcm, ...).
- **[certain]** Native events go back through EventChannels: eventScan, eventBleStatus, eventBleReceive, eventBleAdapter, eventBleLog, plus feature channels (eventLife, eventNotify, eventTranslator, eventTeleprompter, eventTranscribe, eventNavigate, wake_up_event_channel).
- **[certain]** Native has two independent GATT clients, one per temple ("L" and "R"), managed by one singleton. Each handles its own connect, discovery, MTU, CCCD and writes.
- **[certain]** Native does NO chunking, NO serialization and NO request/response matching. It writes whatever byte array Dart gives it. Everything framing-related is in Dart (BleManager).

## 2. GATT service

- **[certain]** Nordic UART Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`.
  - Write characteristic `6E400002-...` (app to glasses). Writes use WRITE_TYPE_NO_RESPONSE on Android 13+ (probable for older API: the characteristic's own write type).
  - Notify characteristic `6E400003-...` (glasses to app), CCCD `00002902-...`.
- **[certain]** One logical stream per temple. There is no second service used for control traffic.

## 3. Scan / discovery

- **[certain]** Native scan uses NO ScanFilter (null filters), ScanSettings mode LOW_LATENCY. Entries with an empty name are dropped; results are de-duplicated by MAC address (list cleared at each scan start). Only the L-side scanner object is used to scan.
- **[certain]** Dart emits `{uuid=address, name, raw manufacturer bytes, rssi}` per device. The name filtering is done in Dart: the device name must contain `_L_` or `_R_` to be assigned to a side (BleDevice.lR; a trailing " L" form is also tested). Pairing of the two temples into one pair object (BleBothDevice.addDevice) is by name.
- **[certain]** Manufacturer-data parsing (native): the scan record must start with a flags AD (len 2), followed by an AD of length 0x15 (21) of type 0xFF (manufacturer-specific). The 20 payload bytes after the type are kept only if their first byte is 1 or 2; otherwise ignored. Dart then decodes these 20 bytes (BleDevice.decodeGlassRaw) into the serial number / model information.
- **[probable]** The first byte (1 or 2) selects a layout version of the serial-number block; the "S100 round / S110 square" frame decoding seen in the community document is applied to this serial.
- **[certain]** scan_filter.dart is NOT an advertisement filter: it only manages history in SharedPreferences (keys `bleMyGlasses`, `bleLastGlass`).

## 4. Connection sequence

Native, per temple (all **[certain]** unless marked):

1. `connectGatt(autoConnect=false, transport=LE, preferred PHY=LE 2M)`.
2. On state CONNECTED: `discoverServices()`, with a 600 ms watchdog re-trying discovery (up to 3 times).
3. About 500 ms after connect a thread calls `createBond()` on every connection (not only the first). Bond state changes and pairing requests are forwarded to Dart on eventBleAdapter. Dart can also call `createBound` (only acts if state is BOND_NONE) and `unpair` (reflection `removeBond`).
4. When services are discovered: find NUS, enable notifications on `...0003` (setCharacteristicNotification + CCCD write ENABLE_NOTIFICATION; the CCCD write is issued twice).
5. Wait 2000 ms, then request MTU **251** (`requestMtu(251)`). Dart may also call method `mtu {lr, mtu}` (default 251).
6. Wait 1500 ms after the MTU request. If the temple is still not marked connected, write a 2-byte "MTU announce" init frame: command `0x4D`, second byte `0xFB` (= 251, i.e. the MTU value itself - the community doc calls it "Init??"). Sent to each temple separately (not left-only).
7. **[probable]** If the init frame has been sent 10 times without success, the app instead writes the ASCII string `#r` (0x23 0x72), the "hard reset" frame, to the temple. The counter resets when the connect event arrives. The retry advances only per connect cycle (no loop), hence "probable".
8. **A temple is declared "connected" ONLY when it sends an inbound frame whose first two bytes are `F5 11`** **[certain]**. That is the "BLE paired / ready" notification; it flips the per-side connected flag and raises Connected to Dart. (The community doc has it as "BLE paired success?" - confirmed.)
9. `onMtuChanged(status 0)` stores the MTU and reports MtuChanged to Dart.

Dart `connect` call **[certain]**: arguments `{L:{uuid}, R:{uuid}}`; L is started first, R immediately after without waiting; a side already connected is skipped. Afterwards a BothState event is generated. There is no strict "left first, wait, then right" ordering in the app at the transport level.

Reconnect **[certain]**:
- If the link drops less than 2000 ms after the connect attempt started, not an intentional disconnect, and the retry counter is under 3, native reconnects immediately (connectGatt again).
- Otherwise it closes the GATT and emits Disconnected; Dart-level autoConnect/startReconnect (BleManager) restarts later using the last glasses stored in preferences.
- Write-failure monitor: more than 3 consecutive write failures spanning more than 3000 ms close the GATT (counter reset on any success).

Master concept **[probable]**: `BleManager.isMaster()` is used when decoding the device-info response (the 0x2C reply) and when picking default sides; `Proto.lR()` returns "R" when both temples are connected (also when only R is), else "L". So R is the default target for single-side requests ("master" = right) - this differs from the community doc which suggests left as primary.

## 5. Write path

- **[certain]** Each native write is an independent coroutine with up to 6 attempts, 10 ms apart. Failure is logged "lost data"; return code 1 or 4 closes the GATT. No inter-packet delay is enforced natively.
- **[certain]** Method `send {data, lr}`: `lr` = "L" or "R" writes that side if connected (returns the write-ack boolean, false if not connected). With `lr` absent, native writes R first then L (the two writes are not acknowledged against each other) and returns null.
- **[certain]** `onCharacteristicWrite` calls a callback registered per FIRST BYTE of the written packet (latest registration wins), giving a per-command write-ack boolean. This is a link-layer ack, not a protocol response.
- **[certain]** Dart `BleManager.sendData(data, {lr, other})` (corrected): with `lr` given, one native `send {data, lr}` and the write-ack boolean is returned. **With no `lr`, it writes BOTH temples** through two native `send` calls, each with an explicit side (so the native "no lr" branch above is not used by this path): first R then L when a boolean flag of the L device object is set, otherwise first L then R (**[probable]**: that flag is not the "connected" flag; its meaning was not resolved). If the first write reports failure, the app pauses **100 ms** (Duration built in code, exact) before the second write; the failed write itself is not repeated.
- **Timing values in sections 4 and 5 are native Java constants and are exact** (checked in the dex: 500 ms bond delay and 2000 ms pre-MTU delay in the GATT callback, 1500 ms after the MTU request, 600 ms discovery watchdog, MTU 251, 3000 ms write-failure window, 10 ms write retry spacing, 2000 ms quick-reconnect window). Only values that Dart code passes as arguments are Smi-tagged in the dump (see section 6).

## 6. Request / response framing (Dart BleManager)

All **[certain]** unless marked.

- **Frame shape**: a request is a raw byte array whose byte 0 is the command. The reply to a request uses the SAME byte 0. There is no sync id, no length field, no CRC at transport level.
- **Matching key**: the pending-request table is keyed by `side + command byte` (for example "R" + "2c"). Only one request per (side, command) can be pending. If a second one is issued with the same key, the old one is completed as failed and its timer is cancelled (log "already exist key").
- **Default side** for `request` without an explicit side: "R" when both temples are connected (or when only R is), else "L".
- **Signature**: `BleManager.request(data, {lr, other, timeoutMs = 500, useNext = false})`.
- **Timeouts** (corrected): if `timeoutMs > 0` a reply timer of `timeoutMs` is armed; on expiry the pending entry is removed, the caller gets a pseudo-reply flagged `isTimeout`, the link monitor counts a send failure and "send Timeout <ms> of <key>" is logged. If `timeoutMs <= 0` no reply timer exists (the request waits until a reply arrives or a newer request with the same key evicts it). **There is no 2 s cap on the reply.** The 2 s limit (Duration constant 2 000 000 us) is a timeout on the *write call* (`sendData`, i.e. the native `send` round trip): if the native write has not returned within 2 s, the pending request is completed as timed out. Long reply timeouts chosen by features are therefore effective.
- **Retry helper**: `requestRetry(data, {lr, retry = 3, timeoutMs = 200})` calls `request` up to `retry + 1` times (useNext false) and returns the first reply that is not a timeout, whatever its status byte. After a timeout it stops early if EITHER temple is not connected (so with a single temple connected there is no retry). Final failure: timeout-flagged reply, log "requestRetry ... timeout of <retry>".
- **Reading caller values**: defaults shown in function prologues are real values, but integers that callers push as named arguments are Smi-tagged in the dump (shown value = 2 x real value). Example: `sendBoth` pushes 500, which is 250 ms.
- **Ack bytes**: a reply is generally `[cmd, status, ...]` with status byte `0xC9` = success/ack. `0xCB` is also accepted as "continue" in multi-packet lists. `0xCA` (and anything else) is treated as failure. Confirmed in `requestList`, `sendBoth`, mic-on, font finish. (Matches the community doc.)
- **requestList(side, packets, timeoutMs)**: sends packets strictly one at a time through `request` with the caller's timeout (no default of its own), waiting for each reply; continues only if reply byte 1 is `0xC9` or `0xCB`; any other value or a timeout aborts and returns false (log "requestList err lr:"). This is the transport for multi-packet commands where each fragment is acknowledged.
- **sendBoth(data, {retry})** (corrected): `requestRetry` on **L** with `retry ?? 0` and timeoutMs **250 ms**; if L times out, returns false (log "sendBoth L timeout"). If L's reply byte 1 is NOT `0xC9`, it returns **true** without sending to R (quirk of the app: only a timeout counts as failure). Otherwise the same request goes to **R** (same retry and 250 ms); returns false only if R times out; R's status byte is not checked. So "both temples" is sequential L then R (differs from native `send` with no side, which fires R then L blindly).
- **"next packet" mode** (`useNext`): the request is not keyed by command; the next non-special inbound frame completes it. Used where the reply command byte is unknown (**probable**: mostly legacy paths).
- **Inbound dispatch order** (handler of eventBleReceive, **[certain]**): ignore type "VoiceChunk"; ignore cmd 0xF4 (device debug log); log (except 0xF1); update the link watchdog; then
  - cmd `0xF5` goes to the event switch (section 8);
  - cmd `0xF6` is ignored by this handler;
  - cmd `0x15` goes to the font/file-transfer retry handler (section 12);
  - any other cmd completes the pending request with key `side+cmd` and cancels its timer.
  Individual features also register their own listeners on the same stream (heartbeat pool, glass-info notifier, navigation, quick-note, calibration), each filtering on byte 0.
- **Single-writer queue** (`SynchronousRequestBuffer`): used by the teleprompter sender; a FIFO of async actions with state idle/busy, run one at a time, flushed when the teleprompter is not running. Not a protocol-level construct.
- **StreamBleBuffer**: OUTBOUND paced text streaming for live AI/transcription display (splits text into word chunks and paces them by a words-per-minute table per language group en/CN/JP/KO). It is not an inbound reassembler.

### 6b. BleService: the second request layer (package even/common/services/ble/ble_service.dart)

A static helper distinct from BleManager's keyed table, used by the newer features in Proto: exit feature (0x18), feature start, display mode, brightness get/set, press-and-hold mode, dashboard configuration and calendar/stock pages, navigation (start, images, route info, arrive, exit, heartbeat), quick-note streaming, transcribe status, device reset, app settings. All **[certain]** unless marked.

- **Inbound routing**: there is no table. BleManager exposes one broadcast stream: EventChannel `eventBleReceive` mapped to `BleReceive` objects (every notification of both temples, before any filtering; the same stream BleManager's own dispatcher reads). Each BleService request subscribes to that stream with `where(matcher)` **before** writing, and the first frame for which `matcher(BleReceive) == true` cancels the subscription and becomes the reply. Nothing is consumed: the same frame is still seen by BleManager's dispatcher (0xF5 switch, keyed pending table) and by every other listener.
- **Matcher**: a predicate supplied by the caller, applied to the whole frame. The request is NOT registered in BleManager's `side+cmd` table, so there is no "already exist key" eviction and several BleService requests with the same command can be outstanding. Shapes found in Proto (byte indexes from 0):
  - command only: `byte0 == cmd && length > 1` (example: exit feature 0x18);
  - sequenced: `byte0 == cmd && length >= 6 && byte3 == the request's sync/sequence id && byte4 == sub-command` (most newer commands);
  - a few check a byte further on (index 5, 9 or 10) for a page/index number (dashboard calendar/stock pages).
  None of the matchers seen tests the side (`lr`) of the frame, so a reply from the other temple can satisfy a pending request **[certain on code; practical impact probable]**.
- **sendOneSide(data, matcher, lr, {timeout = 200 ms}) -> reply or null**: if `lr` is not connected, logs "device not connected" and returns null without writing. Otherwise subscribe, write with `BleManager.sendData(data, lr)`, wait. On timeout: log "onTimeout", cancel the subscription, return null. Errors also give null.
- **sendLeftSide / sendRightSide(data, matcher, {timeout = 200 ms})**: put a `sendOneSide(..., "L"/"R", timeout)` job on a per-side FIFO (`queue` package, parallel = 1, **10 ms delay** after each job; code immediate 20 = Smi 10). One BleService request in flight per temple. This FIFO is independent of `BleManager.request`, which is not queued, so the two layers can interleave on the same temple.
- **sendBothSide(data, matcher, validator, {isInOrder = true, retryCount = 0, timeout = 300 ms}) -> bool**: `validator(reply)` decides success (typically `byte1 == 0xC9`, or a status byte further on); `matcher` only selects which frame is the reply.
  - `isInOrder = true` (default): L through the left FIFO; if no reply or validator false, return false (R is not sent); then R through the right FIFO; result = validator(R reply). Only the per-side timeouts apply.
  - `isInOrder = false`: L and R are queued at the same time; the result is false as soon as one side fails, true when both validators pass; a global timeout of `timeout` on the whole operation (log "sendBothSide onTimeout", result false).
  - Retry: if the result is false and `retryCount > 0`, the whole operation is repeated (both temples again, including the one that had succeeded) with `retryCount - 1`. In-order mode pauses **20 ms** before the retry; parallel mode retries immediately. (Code immediate 40 passed to the `get` package `.milliseconds` extension, which receives a Smi-tagged num and multiplies it by 1000 shown as 2000: real value 20 ms, not 40.)
  - Example: exit feature = single byte `0x18`, matcher `byte0 == 0x18`, validator `byte1 == 0xC9`, in order, retryCount 3.
- **Durations** in the object pool are stored in microseconds: 200 ms = 200000, 300 ms = 300000, 2 s = 2000000.

## 7. Inbound reassembly

- **[certain]** There is no generic reassembly layer for inbound notifications. Each GATT notification (up to MTU-3 = 248 bytes) is delivered as one frame to Dart unchanged, with side ("L"/"R"), type string and RSSI. `BleReceive.getCmd()` is simply byte 0.
- **[certain]** Features that receive multi-packet data from the glasses (quick-note records, glass logs) count and join fragments themselves in their own handlers (per-feature, out of scope).
- **[certain]** Audio packets are the only high-rate inbound stream; they are decoded natively (section 9).
- **[probable]** The 202-byte audio packet and the largest observed requests fit inside MTU 251, so the app never needs an L2CAP-level reassembly. Outbound fragments are sized well under 200 bytes by each feature (examples: 198 for font, 185 for navigation images, see section 12).

## 8. Spontaneous inbound events (cmd 0xF5)

Frame: `F5 <sub> [args]`. Received separately from each temple; handlers mostly ignore which side except where noted.
Values are raw bytes, **[certain]** for the dispatch, meaning column **[probable]** where marked.

| Sub | What the app does with it | Meaning |
|---|---|---|
| 0x00 | exit all functions (isFromGlass), BleEvent exitFunc; also closes display-setting mode | double tap (certain) |
| 0x01 | next/previous page: from the L temple = previous page, from R = next page; teleprompter next page; OS touchpad signal | single tap (certain) |
| 0x02 | BleEvent upHeader | head tilted up (certain) |
| 0x03 | BleEvent downHeader plus "head-down direct push" signal | head tilted down (certain) |
| 0x04 | do-not-disturb ON: BleEvent, exitAll, sets disturb status true | probable: triple tap (community doc "04/05 triple tap") |
| 0x05 | do-not-disturb OFF, sets disturb status false | probable: the other triple-tap variant |
| 0x06 | glass work mode set to value 6; per-side observable updated; device state "wearing" = true | glasses put on / worn (certain on app behaviour) |
| 0x07 | work mode 7, wearing = false | glasses taken off, not in case |
| 0x08 | work mode 8, wearing = false, in-case = true; if previous state was not 8/0x0B, case battery reset to unknown (-2), not charging | put in case, lid open |
| 0x09 | byte 2 == 1 sets "glasses charging" else not charging | glasses charging state (certain) |
| 0x0A | byte 2 = glasses battery %, stored as the MINIMUM of the new value and the stored value (so the displayed level is the lower of the two temples) | battery (certain) |
| 0x0B | same handling as 0x08 (in-case true) | put in case, lid closed |
| 0x0E | byte 2 == 1 sets "case charging" | case charging (certain) |
| 0x0F | byte 2 = case battery % | case battery (certain; the community doc and PROTOCOL_NOTES agree) |
| 0x10 | head-up finished signal (OS) | probable: end of head-up display period |
| 0x11 | link declared ready at native level (see section 4); also stored | BLE ready (certain) |
| 0x12 | byte 2 stored in an observable of the glass-info notifier | probable: a status counter/level; exact meaning not resolved |
| 0x13 / 0x14 | onboarding: begin / finish experience "dashboard" | certain |
| 0x15 / 0x16 | onboarding: begin / finish experience "notification" | certain |
| 0x17 | long press on touchpad starts the voice assistant | certain |
| 0x18 | touchpad released after long press | certain |
| 0x19 | touchpad double tap to continue (voice-assistant flow) | certain |
| 0x1E | dashboard opened (BleEvent dashboardActivate) | certain |
| 0x1F | dashboard closed (BleEvent dashboardInactivate) | certain |
| 0x20 | double tap with a user-assigned function: ignored if silent mode ("double tap failure, is in silent mode"); else by setting: 1 = navigation quick start (probable), 2 = translate, 3 = teleprompter, 4 = transcribe | certain for 2/3/4 |

Notes:
- BleEvent enum values in the app: exitFunc 0, nextPageForTeleprompter 1, upHeader 2, downHeader 3, doNotDisturbON 4, doNotDisturbOFF 5, dashboardActivate 0x1A, dashboardInactivate 0x1B.
- Unknown sub-codes are logged ("eventBleReceive: error").
- Sub-codes 0x0C and 0x0D are not handled anywhere in the app (**probable**: unused or firmware-internal).
- The battery/charge/case handling sits in the home-page glass-info notifier, which listens to the same stream independently of the BleManager switch; the device-state publisher then derives: wearing = (work mode == 6), in-case = (work mode in {8, 0x0B}), plus charging and battery values.
- 0x0F reports only a case percentage, no separate left/right glasses battery here; per-temple glasses battery also comes from the 0x2C device-info reply (section 10).

## 9. Microphone audio (inbound)

- **[certain]** Start: request `0E 01` on one temple; stop: `0E 00` (stop value probable). Reply byte 1 == 0xC9 means mic started. The temple used is L when a setting flag is on and L is connected, else the other temple (R).
- **[certain]** Audio frames: byte 0 = `0xF1`, byte 1 = sequence number (0-255 wrapping), bytes 2..201 = 200 bytes of LC3 audio. Total frame length exactly **202** bytes; frames of other lengths are not treated as audio.
- **[certain]** Native decodes `bytes[2:202]` with an LC3 decoder library (JNI lib "lc3", function decodeLC3) and optionally RNNoise denoising, then feeds PCM to the active consumer chosen by the "mic model" string set from Dart (setMicModel): DebugPlay, DebugClean, DebugSavePcm, modeTranslator, modeTranslatorSync, modeAsr, modeTelepromt, modeMicRawData, azure keyword recognition. In raw-data mode the Dart side receives only an event with the sequence byte (not the audio), so raw audio never reaches Dart.
- **[probable]** LC3 parameters: 16 kHz mono, 10 ms frames, 20 bytes per frame (10 frames per packet; 20 bytes per 10 ms = 16 kbit/s). The decoder is called once per 200-byte payload. Parameters are inside the native library and were not read; they match the community notes.
- **[certain]** `0xF4` frames are device debug text logs, forwarded to a log channel, ignored by the request layer.
- **[certain]** The audio frame is logged only every 50th packet; no per-packet ack is sent by the app.


## 10. Device info request / reply (0x2C)

- **[certain]** Request: 2 bytes `2C xx`, built once by `Proto._deviceInfoData`. In this Android build `xx = 0x01` (the selector is a platform-like predicate folded to a constant `true` here; the other branch gives `0x02`, **[probable]** the iOS value).
- **[certain]** Sent per temple with `requestRetry(lr, retry 5, timeoutMs = caller value or 500 ms)`; matched by the BleManager key `side + "2c"`; on timeout the function returns null.
- **[certain]** Reply parser `DeviceInfo.fromByte(data, isMaster)`, with `isMaster = (lr == "R")`. Byte meanings come from the labels of the debug page that prints them:

| Byte | Meaning |
|---|---|
| 0 | 0x2C |
| 1 | not read by the parser (**[probable]** status) |
| 2 | battery % (debug label "电量", first value) |
| 3 | second value printed next to the battery (meaning not resolved) |
| 4 | battery voltage: `(byte4 + 200) / 100` volts |
| 5 | current (label "电流"), raw unsigned byte |
| 6 | temperature (label "温度"), raw unsigned byte |
| 7, 8, 9 | firmware version `b7.b8.b9`, used when the reply comes from **R** |
| 10, 11, 12 | firmware version `b10.b11.b12`, used when the reply comes from **L** |
| 13..19 | not used, but the parser bounds-checks up to index 19: a reply shorter than 20 bytes makes it throw |

- **[certain]** The decoded object is stored per temple (L or R slot of the pair object). Version "0.0.0" is treated as "version not valid".
- **[probable]** Bytes 7-9 / 10-12 are two version fields (master and slave firmware) present in every reply; the app shows the one matching the temple that answered.

## 11. Keep-alive ("heartbeat") scheduling: BleBeatHeartPool

The app has no single transport heartbeat. `BleBeatHeartPool` is a small scheduler of periodic tasks; the home-page glass-info notifier registers two of them. All **[certain]** unless marked.

| Task | Period | Runs when | What it sends |
|---|---|---|---|
| `foreground_alive_task` | 10 s | app in foreground only | device info `2C 01` to L, then to R (section 10: retry 5, 500 ms) |
| `background_alive_task` | 5 s | app in background only | glass mode `2B` (1 byte) via `requestRetry` (default retry 3, timeout 1000 ms). Reply: bytes 2 and 3 are returned as a pair (meaning: [settings.md](settings.md)). If a temple is disconnected, it starts the reconnect instead (log "start reconnect when bluetooth had disconnected"). |

- Each task carries the command(s) it expects back (`2B` / `2C`), runs once immediately when started, then on a periodic timer.
- **Start**: about 10 s of idle link after both temples are connected (`checkFreeTime`, periodic timer of 10 s, code immediate 20 = Smi 10, cancelled after the first tick). Requires a known glass name and both temples connected; otherwise all tasks are force-stopped ("Glass is null" / "Glass is disconnect").
- **Suspended by activity**: the pool listens to every inbound frame. A frame from a "real" feature stops the tasks and re-arms the 10 s idle timer. Frames that do NOT count as activity: `F1` (audio), `F5` (events), `F4` (logs), `F6`, `22`, `25`, `4B`, `4C`, `0B`, `08`, `26`, `1E`, `01`, `0A` with byte 1 = 6, and any reply whose byte 0 is in a task's own command list (`2B`, `2C`). So the keep-alive only runs when nothing else talks to the glasses.
- **Suspended during upgrades**: both tasks do nothing while any of four static flags set by the firmware-DFU and font-upgrade routines is on (section 12/13).
- **Lifecycle**: on app hide, tasks not allowed in background are stopped; on resume the foreground set is used again.
- **Failure consequence** (link monitor `BleMonitor`, one per temple): every request timeout calls `sentFailed(side)`; any inbound frame from that temple resets the counter. When a temple has more than **5** consecutive failures and more than **21 s** have passed since the first one, the app forcibly disconnects that temple (MethodChannel `disconnect {lr}`), marks it disconnected and calls `autoConnect` 200 ms later. In addition, a failure while not both temples are connected triggers `autoConnect` (unless a reconnect is already running, **[probable]** on the flag meaning).
- Feature-level keep-alives exist outside the pool (payloads in the other files, listed for orientation): teleprompter `25 06 00 seq 04 seq` (seq = counter mod 255, to R, 2000 ms) - this is the "0x25 heartbeat" of the community document, sent only while the teleprompter runs; AI assistant and transcribe heartbeats (own opcodes, 2000 ms); navigation heartbeat `0A ...` through `BleService.sendRightSide`; quick-note streaming heartbeat `1E ...` through `sendBothSide` (retryCount 3).

## 12. File transfer: font upload (0x17 / 0x15 / 0x20 / 0x16) and image paths

### 12a. Font upload (class Dfu, `upgradeFont` / `_updateFont`)

All **[certain]** unless marked.

- **Entry**: manual feature of the debug/upgrade page ("upgradeFont"): the user picks a local file, the app reads its bytes and caches them. No font download URL is used by this path. Target order: **L first** if connected (else R), then the same file to **R** after L succeeded.
- **Opcodes 0x15, 0x16 and 0x20 are built nowhere else in the app.** There is no full-screen BMP upload (the `15 ... 00 1C 00 00 ...` BMP scheme of the community document / Even demo app is absent from app 1.6.5).
- Sequence for one temple:
  1. **Upgrade mode** (only when starting L): single byte `17`, sent with `BleManager.sendBoth` (L then R, 250 ms, no retry; success = no timeout, see section 6). Failure aborts with "进入升级模式失败" ("failed to enter upgrade mode").
  2. Wait **4 s** (log "wait 4 second after into upgrade mode"; code immediate 8 = Smi 4, which confirms the Smi rule for `.seconds`).
  3. Split the file into **198-byte** chunks (last one shorter). Frame = `15 <seq> <chunk>`, `seq` = chunk index & 0xFF (wraps after 256 chunks), so at most 200 bytes per write.
  4. Each frame is written with `sendData` (no reply expected), then a **5 ms** pause (Duration 5000 us). Progress = index x 198.
  5. **Resend request from the glasses**: an inbound frame `15 <seq>` (routed by BleManager's dispatcher, section 6) restarts the send loop from chunk index `seq` (earlier chunks are skipped, the running loop stops at its next packet). A request repeating the same `seq` is ignored ("seq is same"). A restart does not re-enter upgrade mode.
  6. After the last chunk: wait **3 s**, then send **`20 0D 0E`** ("file end") with `request` timeout **3000 ms** (the dump shows 6000, Smi-tagged); on timeout wait 1 s and retry, at most 10 attempts. Success = reply byte 1 == `0xC9`; otherwise "文件结束标志接收错误" ("file end flag receive error").
  7. Wait **1 s**, then send **`16 <CRC32>`**: CRC-32/XZ (crclib `Crc32Xz`: standard reflected CRC-32, init and xor-out 0xFFFFFFFF, same as zlib) computed over the **raw file bytes only** (no `15 seq` headers, no address), written **big-endian** in 4 bytes. `request` with the default 500 ms. Success = reply byte **5** == `0xC9` (**[probable]** reply = `16 <crc echo, 4 bytes> C9`). Failure: "文件CRC校验错误" ("file CRC error") and, when enabled, the whole transfer of that temple is restarted.
  8. Success is logged with the elapsed time; the same sequence (from step 2) then runs for R.
- While a font or firmware upload runs, four static flags are set; they suspend the keep-alive tasks (section 11).

### 12b. Navigation images (transport only; payloads in notes-notifications-dashboard-navigation.md)

- **[certain]** `navigateSendOverviewImage` / `navigateSendDetailsImage`: the image buffer is cut into **185-byte** chunks (`ceil(len / 185)` chunks), with a **30 ms** pause before each chunk (code immediate 60 = Smi 30).
- **[certain]** Frame = 10-byte header + chunk: `0A <len lo> <len hi> <seq> <sub> <total: 2 bytes> <index: 2 bytes> 00 <data>`, where `len` is the whole frame length written little-endian in bytes 1-2, `seq` a global counter mod 255, `sub` = 3 for the overview image and 2 for the details image. **[probable]** byte order of the 2-byte `total` / `index` fields (helper `toUint8List(2)`, not checked).
- **[certain]** All chunks except the last are written blind with `sendData` to L and then to R (no ack). The last chunk goes through `BleService.sendBothSide` (acknowledged, section 6b). The whole image is guarded by a 20 s timeout.
- Other pictures (dashboard "city walk" map, stock chart bitmap) use their own commands through BleService (see [notes-notifications-dashboard-navigation.md](notes-notifications-dashboard-navigation.md)).

## 13. Firmware OTA / DFU

### 13a. What the firmware is

- **[certain]** Firmware arrives as a Zephyr / nRF Connect SDK `dfu_application.zip`; the official app bundles one and downloads newer ones from Even's servers. The bundled one (built 2024-11-14, `"name": "ar_glasses"`) holds two MCUboot images:
  - image 0: application core, board `nrf5340dk_nrf5340_cpuapp`, SoC `nRF5340_CPUAPP_QKAA`, `app_update.bin`, 917 677 bytes, load address 0xC200;
  - image 1: network core, `nrf5340dk_nrf5340_cpunet`, SoC `nRF5340_CPUNET_QKAA`, `net_core_app_update.bin`, 226 144 bytes, load address 0x1008800.
  So each temple runs an **nRF5340** (dual core) with MCUboot.
- **[certain]** The zip's `manifest.json` lists the images (`type, board, soc, load_address, image_index, ...`); each file becomes one McuMgr image (`image = image_index`).

### 13b. Transfer protocol

- **[certain]** The firmware does **not** go through the NUS command channel. It uses the `mcumgr_flutter` plugin (Nordic Android McuMgr library): **SMP over BLE**, service `8D53DC1D-1DB7-4CD3-868B-8A527460AA84`, characteristic `DA2E7828-FBCE-4E01-AE9E-261174997C48` (library UUIDs present in the dex).
- **[certain]** Upgrade configuration: mode **CONFIRM_ONLY**, eraseAppSettings false, estimatedSwapTime 1 s, pipelineDepth 1, byte alignment 4, reassembly buffer 0.
- **[certain]** Sequence (`Dfu._doUpgradeFirmware` / `__updateFirmwareImages`):
  1. **One temple only**: L if connected, else R. No code path uploads the other temple afterwards (the only other caller, `retryInstall`, retries the same side). After success the app just waits for both temples to reboot and reconnect (logs "right side disconnected, waiting for reconnection" / "both sides reconnected", timeout "reboot_time_out"). **[probable]** the temple that received the image updates the other one itself (inter-temple link).
  2. When the target is L: send `17` (upgrade mode) with `BleManager.sendBoth`; for firmware the result is ignored (for fonts it is checked, section 12a).
  3. Cancel any previous manager, create an McuMgr update manager for the temple's BLE address, subscribe to its state stream (timeout 5 min), progress stream (timeout 2 min) and log stream, wait 2 s, then `update(images, configuration)`.
  4. McuMgr state "Upload" is reported as begin, "Reset" as finish; "Success" is logged. Watchdog: no progress event within 20 s after begin, or within 10 s after the previous progress event, kills the manager and reports an error.
  5. On a firmware error for a temple not yet marked done, the app writes `#r` to that temple (section 15). The OTA service then retries automatically up to 5 times (if the BLE link dropped it first waits up to 120 s for reconnection), then asks the user.
- **[certain]** During a DFU: keep-alive tasks are suspended (section 11), the screen is kept awake, and when both temples are connected at the start the "allowAutoConnect" preference is cleared; it is set again and `autoConnect` is called when both temples are marked done.
- Debug page only: manual "OTA_upgrade" (pick a local zip, same path) and "upgradeFont" (section 12a).

## 14. Time synchronisation and uptime

- **[certain]** There is no standalone "set time" command in app 1.6.5: no Proto function builds a frame with the current time outside the dashboard. Local time reaches the glasses only inside the dashboard base-info frame (`dashboardBaseInfo`, built by the dashboard service with a timestamp-with-offset in milliseconds and in seconds, plus weather), see [notes-notifications-dashboard-navigation.md](notes-notifications-dashboard-navigation.md). It is sent when the dashboard service runs an update action, not on connect by itself.
- **[certain]** The reverse direction exists: `getUpTime(lr)` sends `37` with `request` (500 ms) and reads a **little-endian 32-bit** value from reply bytes **2..5** (`sublist(2, 6)` + `readInt32`). The community document puts the 4-byte payload at bytes 1..4; the app reads one byte later. **[probable]** unit = seconds (debug page label "bootTime").
  - Reading note: `sublist(start, end)` through the dispatch table takes `start` unboxed (exact) and `end` boxed (Smi-tagged): the dump shows `start = 2`, `end = 12`, i.e. `sublist(2, 6)`.

## 15. ASCII `#` commands

All are written with `sendData` (no reply expected) unless marked. With no side given, `sendData` writes both temples (section 5).

| Frame | Bytes | Where / meaning |
|---|---|---|
| `#r` | `23 72` | **[certain]** `Proto.restart(caller, {lr})`, log "send restart ble from <caller>". Used: native connection fallback after 10 failed `4D FB` init frames (section 4); after a font upload finishes or fails (reboots that temple); after a firmware DFU error on a temple not yet done; debug page "restart". No reply. |
| `#t` | `23 74` | **[certain]** `Proto.glassDebugInfo(lr)`: sent with `request(..., useNext: true)` because the reply does not start with `23`; the next non-event inbound frame on any key completes it (500 ms). Trailing zero bytes are cut and the rest is decoded as UTF-8 text (community sample: "net build time ..., app build time ..., ver 1.4.5, JBD DeviceID 4010"). Debug page "info". |
| `#l` | `23 6C` | **[certain]** `Proto.debugLog(true)`: turn the glasses' log stream (inbound `F4` frames) ON. Triggered by the official app's support log feature. |
| `#l1` | `23 6C 31` | **[certain]** `Proto.debugLog(false)`: log stream OFF (`IsOpenGlassLog = false`). |
| `#b` | `23 62` | **[certain]** debug page button; **[probable]** the button labelled "set信道" ("set channel", ESB inter-temple radio channel). Meaning not confirmed. |
| `#d10` | `23 64 31 30` | **[certain]** debug page button labelled "关闭常亮" ("turn off always-on"). **[probable]** disables the always-on display test mode. |

No other `#...` literal exists in the app.

## 16. Unsolicited inbound frames (besides `F5` events and `F1` audio)

- **`F4` - glasses log text** **[certain]**: `F4 <text>`; the app takes bytes 1..end, trims trailing padding and converts byte-per-char. BleManager drops `F4` before logging it and before the link monitor (an `F4` frame does NOT count as link activity). While logging is on (`#l`), the official app can forward these lines to its support service; the debug float window also displays them. The app never sends an `F4` frame (the community "Set Debug Mode (0xF4)" command is not used; `#l` / `#l1` are).
- **`F6`** **[certain]**: logged, resets the link monitor, then ignored by BleManager; no handler anywhere else (the keep-alive pool only lists it as "not user activity"). Meaning unknown.
- **`15 <seq>`** **[certain]**: font resend request from the glasses (section 12a).
- No outbound frame starting with `F1`, `F4`, `F5` or `F6` is built anywhere in the app **[certain]**.
- Any other inbound frame only completes a pending `BleManager.request` (key `side + cmd`, or the single "useNext" slot) and/or a BleService matcher; with nothing pending it is dropped after logging. Feature listeners (quick note `21`, navigation, calibration, onboarding) filter the same stream on their own opcodes (see the other files).
- Background traffic that the keep-alive pool does not count as user activity (section 11): `22`, `25`, `26`, `4B`, `4C`, `0B`, `08`, `1E`, `01`, `0A` (byte 1 = 6), plus `F1`, `F4`, `F5`, `F6`.
