# Notes and recordings, notifications, allowlist, dashboard, navigation (official Even app 1.6.5)

Source: analysis of the official Even app 1.6.5. Protocol facts only.
Conventions: "certain" = seen directly in the app and cross-checked; "probable" = inferred. Multi-byte integers are little-endian unless stated.
BothSide = sent to left (L) and right (R) arms, waiting for acks; Sync = per-command counter byte (0..255, wraps).

## Summary table

Side: L = left arm, R = right arm, L+R = BothSide with ack (default 300 ms per side unless stated). "requestList" = one packet at a time, continue only when reply byte 1 is 0xC9/0xCB. Lengths in bytes, header included.

| opcode | sub | name | side | length | reply |
|---|---|---|---|---|---|
| 0x1E | 0x01 | getGlassRecordInfo (list recordings) | R, request 500 ms | 6 (`1E 06 00 sync 01 01`) | `1E LL LL sync 01 count` + count x 9 (`id, ts u32 LE, crc u32 LE`) |
| 0x1E | 0x02 | getGlassRecord (download one) | R, plain write | 6 | stream of `1E .. .. .. 02 total(u16) index(u16) id payload`; done when packets received == total; no ack |
| 0x1E | 0x03 | sendNoteTextSubcontract (text note) | L+R | 9 + <=171 | `1E .. sync 03 recId(2) idx(2) status`, status 0 = ok |
| 0x1E | 0x04 | deleteQuickNoteRecord (0xFF = all) | R, 200 ms | 6 | byte 5 == 0 = ok |
| 0x1E | 0x07..0x0A | streaming quick note (start, text/stop, heartbeat, tips) | L+R, retryCount 3 | 6 / 11+<=180 / 12 / 6 / 6 | byte 5 (or 9) == 0 |
| 0x21 | 0x01 | new-recording announcement (glasses -> app) | from glasses | 6 + 9 x count | none (app downloads) |
| 0x4B | - | sendNotify (JSON `ncs_notification`) | L, requestList 1000 ms/packet, 6 attempts | 4 + <=176 (`4B 00 count index`) | 0xC9 / 0xCB per packet |
| 0x4C | - | removeNotify | L, plain write | 5 (`4C` + msg_id u32 BE) | not awaited |
| 0x04 | - | app whitelist JSON | L, requestList 300 ms/packet, 3 attempts | 3 + <=177 (`04 count index`) | 0xC9 / 0xCB per packet |
| 0x06 | 0x01 | dashboardBaseInfo (time, weather, formats) | L+R, retryCount 3 | 22 | ack (sync + sub echoed) |
| 0x06 | 0x03 | configDashboardCalendar | L+R per packet | 9 + <=180 | ack per packet |
| 0x06 | 0x04 | configDashboardStock | L+R, 1 s per packet | 9 + <=180 | ack per packet |
| 0x06 | 0x05 | configDashboardNews | L+R per packet | 9 + <=180 | ack per packet |
| 0x06 | 0x06 | configDashboardMode (layout + main widget) | L+R, retryCount 3, 1 s | 7 | ack |
| 0x06 | 0x07 | city walk / map pane | L then R single-side sends not awaited, last packet L+R awaited | 9 + <=180 | ack on last packet |
| 0x22 | 0x01 | fetchDashboardData | R, request 500 ms | 5 | awaited, unused |
| 0x56 | 0x08 | exitDashboardWhileBeAwake | L (1000 ms), then R (2000 ms) if L passed | 6 (`56 06 00 seq 08 00`) | `byte5 == 0x00` |
| 0x0A | 0x00 | navigateStart | L+R, retryCount 3, 2 s | 6 | ack |
| 0x0A | 0x01 | navigateSendRouteInfo | L+R, retryCount 3, 2 s | 10 + 5 zero-terminated strings | ack |
| 0x0A | 0x02 | navigateSendDetailsImage | L then R plain, last L+R | 9 + <=185 | ack on last packet |
| 0x0A | 0x03 | navigateSendOverviewImage | L then R plain, last L+R | 10 + <=185 | ack on last packet |
| 0x0A | 0x04 | navigateHeartBeat | R, 2 s | 6 | ack |
| 0x0A | 0x05 | navigateExit | L+R, retryCount 5, 3 s | 6 | ack |
| 0x0A | 0x06 | navigateArrive | L+R, retryCount 5, 2 s | 7 + text + 00 | ack |
| 0x58 | - | calendar events | not present in 1.6.5 (calendar only via 0x06/0x03) | - | - |

Differences with this app (before the fixes listed in [README.md](README.md)), the community document and [PROTOCOL_NOTES.md](../PROTOCOL_NOTES.md): 0x1E/0x02 download fields mis-parsed by G1_Extended (works by accident, see 3.1); recordings start with 400 bytes the app drops; 0x4B byte 1 is a constant 0x00 and the official app sends 0x4B LEFT only with per-packet ack; 0x4C carries the msg_id (u32 big-endian); 0x06/0x01 is 22 bytes (extra date-format byte); news/stocks/calendar use 1-based u16 index and 180-byte chunks exactly as G1_Extended's even-utils port.

## SECTION 1 - Quick notes (audio recordings stored on the glasses), opcode 0x1E

Frame shape for every 0x1E command: `1E | len lo | len hi | sync | sub | args...`, `len` = full packet length (header included, 16-bit LE). Sub-commands seen in this slice: 0x01 list recordings, 0x02 download recording, 0x03 push note text, 0x04 delete recording, 0x07/0x08/0x09/0x0A streaming (see section 2).

### 1.1 getGlassRecordInfo - list recordings on the glasses (0x1E sub 0x01)
- Request (certain): `1E 06 00 sync 01 01` (6 bytes; the last byte is a constant 1, meaning unknown). Sent to the RIGHT arm only through the plain request helper (default timeout 500 ms, no retry).
- Response (certain for layout, probable for semantics): `1E LL LL sync 01 count` then `count` records of 9 bytes each starting at offset 6: `id (u8) | timestamp (u32 LE) | crc (u32 LE)`. A response shorter than 7 bytes is treated as "no recordings" (the app logs this case). A record is kept only if id, timestamp and crc are all > 0 (certain). Timestamp: logged only, never stored (probable unit: Unix seconds, see 3.4). crc: never checked against the audio; it is the duplicate key of the recording (see 3.4).
- Callers: the app lists records, then downloads each one with 1.2 and deletes it with 1.3.

### 1.2 getGlassRecord - download one recording (0x1E sub 0x02)
- Request (certain): `1E 06 00 sync 02 id` where `id` = record id from 1.1 (value mod 255; byte). Sent to the RIGHT arm only with a plain write, no ack wait; sync = the shared counter (advances by one).
- Response stream (certain): the app subscribes to incoming packets and keeps those with cmd 0x1E, length > 10, byte[4] == 0x02 and byte[9] == the requested id. Layout of each data packet: `1E LL LL sync 02 | total (u16 LE) | index (u16 LE) | id (u8) | payload...` where payload starts at byte 10. `total` = number of packets of the transfer (taken from the first packet received); `index` is the packet number (the app only sorts by it; probably 1-based, see 3.1); packets are stored in a map keyed by index (duplicates overwritten), a packet counter is incremented per packet.
- Completion (certain): when the packet counter equals the `total` value read from the current packet, timers are cancelled and the payloads are sorted by index and concatenated into one buffer (the blob = LC3 audio frames, probable since the app later converts "lc3ToPcm" in the streaming code). No per-packet ack is sent.
- Timeouts (certain, corrected by section 3): 10 s stream timeout; a 1 s inactivity timer restarted after every packet. On timeout/error: if received/total > 0.9 the partial data is accepted (concatenated), otherwise the transfer fails and the caller re-queries and retries: up to 5 retries (6 attempts), then it restarts the BLE link.
- Max payload per packet: not fixed by the app; the glasses decide (an MTU-sized chunk, probable ~ 200 bytes).

### 1.3 deleteQuickNoteRecord - delete a recording (0x1E sub 0x04)
- Request (certain): `1E 06 00 sync 04 id` where `id` = record id mod 255, or 0xFF when no id is given (meaning: delete ALL recordings; only the debug screen button "delete all record" does this - certain). Sent to RIGHT arm only (sendRightSide, default 200 ms timeout), with a 20 ms pause before and after (certain).
- Matcher (certain): cmd 0x1E, length >= 6, byte[3] == sync, byte[4] == 0x04. Success: byte[5] == 0x00.
- Used right after a successful download (1.2), and also, without download, for listed recordings whose crc is already known locally (see 3.4).

### 1.4 receiveQuickNoteRecordData
Internal helper of 1.2 (listener + reassembly described above). Not a command.

### 1.5 setGlassQuickNoteText - push a text note to the glasses (0x1E sub 0x03)
Wrapper (text/title variant) around the packet sender 1.6. Signature seen: (title string, recordId int, body string).
- The app builds one logical stream S (little-endian lengths): `recordId (low byte)` | `mode (1 byte)` | `len1 (1 byte, low byte of length of block 1)` | `block 1 = UTF-8 of body` | `len2 (u16 LE)` | `block 2 = UTF-8 of title`. `mode` (values certain, meaning probable): 0 = both empty, 1 = body and title present, 2 = body only, 3 = title only. When a string is empty its block is replaced by a single 0x00 byte (certain).
- S is cut into packets of at most 171 payload bytes; each packet is sent with 1.6 (9-byte header + <=171 = <=180 bytes on the wire). Packets are sent strictly in order, each acknowledged by both arms before the next; the function returns false at the first failure, true after the last.
- Quirk (probable): the loop offsets start at 9 for the first packet and at index*180 for later ones, with a 171-byte window, so for bodies above ~340 bytes some 9-byte gaps appear between packets. Short notes (typical use) are not affected.
- Packet numbering is 1-based.

### 1.6 sendNoteTextSubcontract - one text-note packet (0x1E sub 0x03)
- Frame (certain): `1E | len lo | len hi | sync | 03 | recordId (u16 LE) | packIndex (u16 LE, 1-based) | chunk`.
- Sent BothSide (L and R, ack required, default timeout, no explicit retries). Sync is a new counter value per packet.
- Matcher: cmd 0x1E, length >= 10, byte[3] == sync, byte[4] == 0x03. Success: byte[9] == 0x00 (response echoes recordId and packIndex at bytes 5..8, status at byte 9; this agrees with the sample in the protocol document: `1e 10 00 29 03 01 00 01 00 00`).
- Disagreement with "Even Realities G1 BLE Protocol.txt": the document leaves 0x1E as "TODO" and its sample payload (`03 00 01 00 01 00 00`) is shorter than what this version builds; the first payload bytes here are recordId, mode, len1 as described in 1.5 (probable).

## SECTION 2 - Streaming quick note (live transcription of speech, 0x1E sub 0x07..0x0A)

All five commands are BothSide with ack, retryCount 3, default timeout 300 ms, new sync per call. Generic matcher (certain): cmd 0x1E, length >= 6, byte[3] == sync, byte[4] == sub. Generic success: byte[5] == 0x00.

### 2.1 startStreamingQuickNote (sub 0x07)
`1E 06 00 sync 07 01`. Byte 5 constant 1 (meaning unknown). Certain.

### 2.2 streamingQuickNoteText (sub 0x08) - send live text
- Arguments: (flag bool, text string). Text is UTF-8 encoded and cut into 180-byte chunks; packets = ceil(bytes/180).
- Frame per packet (certain): `1E | len lo | len hi | sync | 08 | total packets (u16 LE) | packet number (u16 LE, 1-based) | 00 | flag (0/1) | chunk(<=180 bytes)`. So 11-byte header, up to 191 bytes on the wire. Flag meaning is unknown (probable: "this is the final/complete text" vs partial); byte 9 is 0 for normal packets.
- Matcher: cmd 0x1E, length >= 10, byte[3] == sync, byte[4] == 0x08. Success: byte[9] == 0x00. retryCount 3 per packet; sends sequentially and returns false on first failure.

### 2.3 stopStreamingQuickNote (sub 0x08, special packet)
- Frame (certain): `1E 0C 00 sync 08 01 00 01 00 01 00 00` (12 bytes). Same layout as 2.2 with total=1, packet=1, byte[9]=1 (probable "end of stream"), flag 0 and one zero payload byte.
- Matcher: cmd 0x1E, length >= 9, byte[3] == sync, byte[4] == 0x08. Success: byte[5] == 0.

### 2.4 streamingQuickNoteHeartBeat (sub 0x09)
- Frame (certain): `1E 06 00 sync 09 n` with n = an incrementing counter kept by the caller (starts at 0, the byte is the raw counter).
- Matcher: cmd 0x1E, length >= 7, byte[3] == sync, byte[4] == 0x09, and byte[6] == (n mod 255). Success byte[5] == 0. (So the response echoes the counter at byte 6; certain for the check, probable for the layout `1E LL LL sync 09 status n`.)

### 2.5 streamingQuickNoteTips (sub 0x0A)
- Frame (certain): `1E 06 00 sync 0A v` where v is 2 in the normal case and 0xFF (-1) in another case (the caller uses -1 under a threshold condition, probably "no tips / low level"; probable). Meaning of v: probable "tip/status code displayed on the glasses during dictation".
- Generic matcher and success.

## SECTION 3 - Audio notes: verification and details

Scope: re-checks sections 1.1-1.4 against the app's quick-note service. Where this section disagrees with section 1, this section wins.

### 3.1 Download 0x1E sub 0x02 - packet layout, index, end of transfer
- Request `1E 06 00 sync 02 id`, written to the RIGHT arm with a plain write (no ack awaited). [certain]
- Packets accepted by the app (all must hold) [certain]: byte0 == 0x1E; length > 5 and byte4 == 0x02; length > 10 and byte9 == the requested id. The listener does not filter by arm. Byte 3 of download packets is ignored.
- Layout [certain]: `1E | b1 | b2 | b3 | 02 | total (u16 LE, bytes 5-6) | index (u16 LE, bytes 7-8) | id (byte 9) | audio payload (byte 10 to end)`. Both u16 are read little-endian.
- Index base: the app never interprets the index value; it is only the key of a map, sorted ascending at the end before concatenation. The official app therefore does not tell whether it is 0- or 1-based. [certain]
- End of transfer [certain]: a counter is incremented for EVERY accepted packet (duplicates included, while the map overwrites duplicates); the transfer is complete when that counter equals the `total` of the packet just received. No end flag, no "last index" test, no ack.
- Timers [certain]: inactivity timer 1 s (restarted after each packet), stream timeout 10 s (the app's own log line reads "receiveQuickNoteRecordData 10s timeout"). On timeout or error the partial data is still accepted if received/total > 0.9 (total = value of the first packet), otherwise the download fails.
- Failure handling [certain]: on failure the app re-queries the list and retries, up to 5 retries; at the 6th consecutive failure it resets the counter, restarts the BLE link ("quick note" reason) and shows a "connection lost" dialog. The whole task (query + download + delete + note creation) is bounded by a 30 s timeout.

What this app's download parser got right or wrong before it was fixed (now `VoiceNoteDownload` in `lib/models/g1/voice_note.dart`):
- `totalPackets = (data[5] << 8) | data[4]` - WRONG. data[4] is the sub-command (0x02). Correct: `data[5] | (data[6] << 8)`. [certain]
- `currentPacket = (data[7] << 8) | data[6]` - WRONG. data[6] is the high byte of total. Correct: `data[7] | (data[8] << 8)`. [certain]
- End test `currentPacket + 2 == totalPackets` - WRONG as written, but it works by accident: for total < 256 it reduces to "index == total", i.e. it fires on the last packet only if the index is 1-based and the last packet arrives last. Since this code was pinned against real firmware (Fahrplan), the index is probably 1-based (1..total); every other multi-packet transfer built by this app (0x1E/0x03 text notes, 0x06 calendar/news/stocks/map, 0x0A images) also numbers packets from 1. [probable] Recommended: count the packets and stop when count == total (official behaviour), plus a 1 s inactivity timer.
- Ordering by `data[3]` (seq) - WRONG key. The official app orders by the u16 at bytes 7-8 and ignores byte 3. [certain]
- `index = data[9] - 1`, then delete with `index + 1` - net effect correct: the delete uses byte 9, i.e. the id from the list. [certain]
- Payload from byte 10 - correct. [certain]

### 3.2 Announcement 0x21 from the glasses (new recording)
- The official app DOES listen for 0x21 (QuickNoteBleService._observeRecordPush). Accepted when [certain]: byte0 == 0x21, length > 6, byte4 == 0x01, byte5 >= 1.
- The frame is parsed by the same function as the 0x1E/0x01 reply [certain]: count = byte 5, then `count` records of 9 bytes from byte 6: `id (u8) | timestamp (u32 LE) | crc (u32 LE)`. So a 0x21 push is `21 | len lo | len hi | sync | 01 | count | records...` (bytes 1-3 are not checked by the app; length LE + sync is what real captures show). [certain for parsing, probable for bytes 1-3]
- No reply/ack is sent to 0x21. [certain]
- Effect: the parsed list is queued as a "record task" exactly like the polling path, but without sending 0x1E/0x01 first. [certain]
- G1_Extended VoiceNoteNotification: layout correct; its extra check `count == (len - 6) / 9` is stricter than the official app (harmless if the firmware is consistent). [certain]

### 3.3 When the official app synchronises recordings
- Pre-condition "ready" (all required) [certain]: glasses connected, user logged in, home screen loaded, glasses WORN (wearing detection). If not ready, nothing is fetched.
- Triggers [certain]:
  1. State change of connection, wearing or home-loaded (and service start): after a 1 s debounce, if ready, the app waits 3 s more and then sends the list query 0x1E/0x01.
  2. App back to foreground (Android onResume): list query.
  3. 0x21 push from the glasses: immediate task with the pushed list (no list query).
  4. After a live ("streaming") quick note has been saved: list query.
  5. After a successful download, if the list held more than one recording: list query again (recordings are fetched one at a time).
  6. After a failed download: list query again (max 5 retries, see 3.1).
- Not tied to any 0xF5 event in this service. There is no periodic polling of recordings (the 3 s periodic timer of this service only pushes text notes to the glasses). [certain]
- If another BLE-heavy feature is running (translation, teleprompter, firmware update, onboarding, navigation), the task is postponed by 5 s and re-queued. [certain]
- Processing order for one task [certain]: (1) list (pushed or queried); (2) every listed recording whose crc equals the crc stored with an existing local note is deleted on the glasses (0x1E/0x04) without being downloaded; (3) the first remaining recording is downloaded (0x1E/0x02); (4) on success it is deleted on the glasses (0x1E/0x04, result only logged, not awaited) and a local note is created from the audio; (5) next recording via a new list query.

### 3.4 Timestamp and crc
- Both are u32 little-endian. [certain]
- Timestamp: only written to the log; it is not kept in the record object nor used for the note. Unit not visible in the app; the real capture quoted in G1_Extended (`9a a1 7a 67` = 0x677AA19A) decodes to 2025-01-05 in Unix seconds, so: Unix epoch seconds. [probable]
- crc: never verified against the downloaded audio (no checksum computation anywhere in the path). It is stored in the created note as `recordFileCrc` and used as the identity of a recording: a listed recording whose crc is already known locally is considered imported and is deleted from the glasses without download; note creation is refused if a note with the same crc exists. [certain] Algorithm of the crc: not visible (computed by the firmware). [-]

### 3.5 Audio format of the downloaded blob
- The blob is raw LC3 frames, no container, no per-frame header. [certain]
- Codec parameters (native decoder used for recordings, `Cpp.decodeLC3` in liblc3.so) [certain]: frame duration 10 ms, sample rate 16 kHz, mono, 20 bytes per frame (16 kbit/s); output = 16-bit signed PCM, 160 samples (320 bytes) per frame. The decoder walks the input 20 bytes at a time and ignores a trailing partial frame.
- The app saves the blob to `<app support dir>/.../quick_note/<note>/record.lc3`, but DROPS THE FIRST 400 BYTES when the blob is longer than 400 bytes (400 bytes = 20 frames = 200 ms of audio, probably the touch/start click). [certain for the cut, probable for the reason]
- Conversion: record.lc3 -> PCM (method channel `quickNoteLc3ToPcm`, decoder above) -> optional noise reduction (ffmpeg / rnnoise) -> Ogg/WAV for playback and cloud speech-to-text. [certain for the decoder, probable for the rest of the chain]
- Same codec settings as the live microphone stream: the live path decodes 200 bytes per mic packet (bytes 2..201 = 10 frames of 20 bytes). [certain]
- G1_Extended `LC3.decodeLC3(encoded)` on the whole blob is the right idea; to match the official app, skip the first 400 bytes before decoding. [certain]

### 3.6 Constants
- 0x1E/0x01 request byte 5 is always 0x01. Its meaning is not visible in the app (the reply and the 0x21 push carry the record count at that position). [certain that it is constant; meaning unknown]
- The sub-command byte 0x01 at byte 4 is shared by the list reply and by the 0x21 push (both parsed by the same code). [certain]
- 0x1E/0x04 with id 0xFF = delete all recordings (debug-screen button "delete all record"; the production flow always passes an id). [certain]
- Ids are sent as `id mod 255` (not `& 0xFF`): an id of 255 would be sent as 0. [certain] Ids seen in practice are small (1..n).
- Sync byte of 0x1E requests: shared counter, reset to 0 when it reaches 255 (so 0..254). [probable]

### 3.7 What this app does now
- Download packets are parsed as `total = d[5] | d[6] << 8`, `index = d[7] | d[8] << 8`, `id = d[9]`, payload `d[10..]`, kept by index; only packets with `d[4] == 0x02` and the requested id are taken; the transfer completes when the count reaches `total`; the first 400 bytes are dropped before decoding.
- The list is requested (`1E 06 00 sync 01 01`, right temple) a few seconds after the pair connects and after each saved recording, so recordings made while disconnected are fetched one after another. A 0x21 announcement still works as before.
- A recording whose crc was saved during this run is deleted again instead of being downloaded twice (in memory only, not across restarts).
- The raw LC3 reaches disk first, as the official app writes its record.lc3, and the glasses copy is deleted as soon as it is there; decoding and transcription come after. A decoder failure therefore cannot leave the recording on the glasses to be fetched again at every connection.
- Not done: the 1 s inactivity timer, the 10 s overall limit with acceptance above 90 %, and the retry/reconnect policy. A stalled transfer is replaced by the next list after 10 s; the recording stays on the glasses until the phone has saved it.

## SECTION 4 - Notifications 0x4B (sendNotify) and 0x4C (removeNotify)

Source: sendNotify, _getNotifyPackList and removeNotify, the home page event handler, and the app's Android notification listener `com.even.g1.notify.G1NLService` (the JSON is built there; the Flutter side only wraps and sends it).

### 4.1 JSON payload [certain]
The Android notification listener builds this map and passes it to Dart as `{"type":"add","data":{...}}`; Dart wraps it as `{"ncs_notification": data}`, `jsonEncode`s it (compact, no spaces) and UTF-8 encodes it. Keys, in this order:
| key | type | value |
|---|---|---|
| msg_id | integer | id of the row stored in the app's local notification database (auto-increment, long); the notification is dropped if the insert returns -1 |
| action | integer | always 0 for a new notification |
| app_identifier | string | Android package name; cut to its first 31 characters when it is 32 characters or longer |
| title | string | `android.title` extra (some apps: rewritten from text/bigText/textLines) |
| subtitle | string | `android.subText` extra, often "" |
| message | string | `android.text` extra (or bigText / last text line for some messaging apps) |
| time_s | integer | post time in Unix SECONDS |
| date | string | post time formatted `yyyy-MM-dd HH:mm:ss`, phone local time zone |
| display_name | string | application label (human-readable app name), "" if unknown |
No `type` key. No emoji stripping (the sanitizer is a no-op in 1.6.5). Notifications from the app itself, "android", system UI, settings, Play Store, Google "as", media-channel notifications and empty ones (no title and no text) are not forwarded. No whitelist filtering on the phone side (the glasses presumably filter with the 0x04 whitelist by app_identifier). [certain for the app, probable for the glasses-side filtering]

### 4.2 Packets [certain]
- The UTF-8 JSON is cut into chunks of at most 176 bytes; count = ceil(len / 176).
- Each packet: `4B | 00 | count | index | chunk`, i.e. a 4-byte header, index 0-based (0..count-1), so at most 180 bytes on the wire. Byte 1 is ALWAYS 0x00 in the official app (it is not a per-notification id).
- Count and index are single bytes (no 16-bit fields).

### 4.3 Side, acks, retries [certain]
- Sent to the LEFT arm only, one packet at a time through requestList: each packet waits for a reply (timeout 1000 ms per packet); the next packet is sent only if byte 1 of the reply is 0xC9 (success) or 0xCB (continue). Any other reply or a timeout aborts the list.
- On failure the whole list is resent, up to 6 attempts in total.

### 4.4 0x4C - remove a notification [certain]
- Triggered when the phone notification is removed: Android passes the list of affected msg_ids (`{"type":"remove","data":[ids]}`); Dart sends one 0x4C per id.
- Frame: `4C | msg_id (u32 BIG-endian)` = 5 bytes, no length/sync byte.
- LEFT arm only, plain write, no ack awaited.

### 4.5 Comparison with G1_Extended / documents
- G1_Extended `notification.dart`: same JSON keys and order, same 176-byte chunks, 0-based index, 4-byte header - correct. Differences: byte 1 is 1 in G1_Extended, 0 in the official app (both apparently accepted); G1_Extended sends to both arms, the official app to the LEFT arm only with per-packet ack (0xC9/0xCB) and retries. The official app does not strip emojis.
- PROTOCOL_NOTES.md calls byte 1 "notifyId": in 1.6.5 it is a constant 0. Its claim that left-only routing prevents display is not supported by the official app, which is left-only; the 3-byte header was probably the real bug. [probable]
- "Even Realities G1 BLE Protocol.txt" (0x4B = `4B count seq payload`, left arm, 180 bytes max): the side is right; the header is missing the 0x00 byte.
- 0x4C: G1_Extended's debug button sends a bare `4C` to both arms; the official frame carries the msg_id (u32 big-endian) and goes to the left arm.

## SECTION 5 - Notification whitelist 0x04 (sendNewAppWhiteList / sendNewAppWhiteListJson / _getPackList)

### 5.1 JSON [certain]
Built by sendNewAppWhiteList(apps, appEnable, calendarEnable, callEnable, iosMailEnable, msgEnable), compact `jsonEncode`, UTF-8:
`{"calendar_enable":bool,"call_enable":bool,"msg_enable":bool,"ios_mail_enable":bool,"app":{"list":[{"id":"<package name>","name":"<app label>"},...],"enable":bool}}`
- Key order as above; all five flags are JSON booleans.
- `list` contains only apps with a non-empty id (package name); each entry has exactly `id` and `name` (name may be null).
- When the user disables notifications, the app sends the same JSON with every flag false (the list is still sent).
- sendNewAppWhiteListJson(json) is also called directly with a JSON string restored from local storage (key "enable_notification_info") from the home page (probable: at start-up / reconnection).

### 5.2 Packets [certain]
- Chunks of at most 177 bytes; count = ceil(len / 177).
- Packet: `04 | count | index | chunk` (3-byte header, index 0-based, so at most 180 bytes). No length, no sync byte, no notify-id byte.

### 5.3 Side, acks, retries [certain]
- LEFT arm only, through requestList: per packet timeout 300 ms; continue only on reply byte 1 = 0xC9 or 0xCB.
- Whole list retried up to 3 attempts in total.

## SECTION 6 - Dashboard 0x06

Common frame for every 0x06 command [certain]: `06 | len lo | len hi | sync | sub | payload`, len = full packet length (16-bit LE, header included); sync from the shared dashboard counter (`_getSyncId`). Generic matcher: cmd 0x06, length >= 6, byte 3 == sync, byte 4 == sub.
Update sequence used by the app (debounced "markNeedsUpdate", skipped while translation / teleprompter / firmware update / onboarding / navigation runs) [certain]: 0x06/0x06 mode -> 0x06/0x01 base info -> 0x06/0x03 calendar -> 0x06/0x04 stocks (only if the main widget is stocks) or 0x06/0x05 news (only if the main widget is news) -> 0x22/0x01 fetch (section 6.3).

### 6.1 dashboardBaseInfo - time, weather, formats (0x06 sub 0x01) [certain]
- Frame (22 bytes): `06 16 00 sync 01 | t_s (u32 LE) | t_ms (u64 LE) | weather icon (u8) | temperature (s8) | temp unit | time format | date format`.
- t_s / t_ms: phone time in seconds / milliseconds PLUS the time-zone offset (local wall-clock time expressed as an epoch value), both little-endian.
- weather icon: weather code from the app's weather model (0xFF if no weather). temperature: degrees CELSIUS, rounded, one byte (0xFF if unknown); the unit byte only tells the glasses how to display it.
- temp unit: 0 = Celsius, 1 = Fahrenheit. time format: 0 = 24 h, 1 = 12 h. date format (month/day order): 0 for United States, Philippines, Canada, Belgium, China, Japan, South Korea; 1 for Sweden, Norway, Finland, Poland; 2 for every other country (exact rendering of each value not visible) [mapping certain, meaning probable].
- Sent BothSide, retryCount 3, default timeout (300 ms).
- Difference with the older public layout (`06 15 00 sync 01` + 4 + 8 + icon + temp + C/F + 24h/12h, 21 bytes): 1.6.5 adds a 22nd byte, the date-format byte. [certain]

### 6.2 configDashboardMode (0x06 sub 0x06) [certain]
- Frame (7 bytes): `06 07 00 sync 06 | layout | main widget`.
- layout: 0 = full, 1 = dual, 2 = minimal.
- main widget: 0 = quick notes, 1 = stocks, 2 = news, 3 = calendar, 4 = map ("hand-out map"), 0xFF = health (the app's own enum order is different: quick_note 0, health 1, stocks 2, calendar 3, news 4, map 5 - it is remapped before sending).
- BothSide, retryCount 3, timeout 1 s.

### 6.3 fetchDashboardData (opcode 0x22 sub 0x01) [certain]
- Frame: `22 05 00 sync 01` (5 bytes), sync = a mod-255 counter.
- Sent to the RIGHT arm with the plain request helper (500 ms timeout). The reply is awaited but not used by the dashboard service (probable purpose: ask the glasses to refresh / report dashboard state).
- Sent at the end of every dashboard update.

### 6.4 configDashboardCalendar (0x06 sub 0x03) [certain unless marked]
- Logical payload P: `layout | main widget | status | [event count | events...]`
  - layout and main widget: same values as 6.2.
  - status: 0 = loading, 1 = no calendar source selected (empty selection list), 2 = no events, 3 = events follow [codes certain, labels probable].
  - Only when status = 3: `event count (u8)` then each event as tagged length-prefixed UTF-8 strings: `01 len title | 02 len time | 03 len location` (len = 1 byte).
  - title: newlines removed, trimmed, cut to fit the pane width (or to 64 bytes with an ellipsis, emoji removed). time: "start-end" in "HH:mm" (24 h setting) or "hh:mm" (12 h setting), end at midnight shown as "24:00"/"12:00", prefix "Tmr " for tomorrow; cut to 32 bytes. location: cut to the pane width or 32 bytes.
- P is cut into chunks of at most 180 bytes; packets = ceil(len(P) / 180).
- Packet: `06 | len lo | len hi | sync | 03 | total (u16 LE) | index (u16 LE, 1-based) | chunk`. New sync per packet.
- Each packet BothSide with ack (default retry 0, 300 ms); the next packet only after success; abort (return false) on failure or if the user changed layout/main widget meanwhile.
- The events come from the phone calendar (selected calendars), refreshed when the dashboard is updated.

### 6.5 configDashboardNews (0x06 sub 0x05) [certain unless marked]
- Logical payload P: `layout | main widget | news status | [slot | operation | 01 | src len (u8) | source | 02 | title len (u16 LE) | title]`.
  - news status: 0 = news list empty (shown as "loading"), 1 = no source selected (first flag argument), 2 = news follow, 4 = "data shortage" (`isDataShortage`, i.e. too few sources/items). Status 3 is never sent. [codes certain; labels probable, they agree with even-utils: loading / noDataSelected / showNews / showMoreSources]
  - Only for status 2: one message PER news item (not one message for all): `slot` = item position 1..n (probably at most 4, as in even-utils), `operation` = always 0x01 (update). Source: UTF-8 cut to 40 bytes (or to the pane width); title/body: UTF-8 cut to 279 bytes with ellipsis.
  - Other statuses: P is just `layout | main widget | status`.
- Each P is chunked like the calendar: chunks of at most 180 bytes, `06 | len lo | len hi | sync | 05 | total (u16 LE) | index (u16 LE, 1-based) | chunk`, new sync per packet, BothSide with ack (300 ms), next packet only after success.
- Whole command retried up to retryCount = 3 times when a send fails.
- Comparison with G1_Extended `dashboard_panel.dart` (from even-utils): layout, pane id 2, display mode, slot, operation 1, tag 01 + u8 length, tag 02 + u16 length, 180-byte chunks, u16 total / u16 1-based index - all identical to the official app. Differences: limits (official: source 40 bytes, body 279 bytes; G1_Extended: 64 and 280); the official app never sends operation 0x02 (delete) - clearing is done by sending status 0/1/4 without items. [certain]

### 6.6 configDashboardStock (0x06 sub 0x04) [certain unless marked]
- Logical payload P: `layout | main widget | stock status | [slot | operation | fields...]`.
  - stock status: 1 = no stock selected (watch-list empty), 0 = stocks selected but no quote data yet (loading), 2 = quotes follow [codes certain, labels probable].
  - For status 2 the app sends one message per slot, slots 1..4 (always four messages):
    - slot with a stock: `slot | 01 (update) | 01 len symbol | 02 len name | 03 len price | 04 len change | 05 len percent | 06 01 up/down | 07 chart len (u16 LE) chart`. All strings UTF-8 with a 1-byte length; symbol cut to 32 bytes, name cut to the pane width, price/change/percent cut to 16 bytes ("--" when missing). up/down: one byte from the quote (0 when unknown; sign convention not visible). chart: line-chart bitmap rendered by the app (`toBitmap`), preceded by its 16-bit LE length (bitmap format not decoded here).
    - empty slot: `slot | 02` (operation 2 = delete).
  - Other statuses: P = `layout | main widget | status`.
- Chunking like 6.4/6.5: <= 180-byte chunks, `06 | len lo | len hi | sync | 04 | total (u16 LE) | index (u16 LE, 1-based) | chunk`, BothSide with ack, per-packet timeout 1 s, sending aborted if layout/widget changed meanwhile.
- Whole command retried up to retryCount = 3 (default parameter) on failure.

### 6.7 City walk / map pane (0x06 sub 0x07: configCityWalkData + wrappers) [certain unless marked]
- Logical payload P: `layout | main widget | map data`, sent only if the current layout/main widget still select the map pane (otherwise returns false). Map data by wrapper:
  - configCityWalkLoading: `00`.
  - configCityWalkReduceMovement: `01`.
  - configCityWalkMapData: `02 01 | map bitmap` (1-bit pane image built by the app).
  - configCityWalkArrowData: `03 | u16 LE | u16 LE | arrow sprite` (the two u16 are the arrow position, first argument first; probable x then y).
  These agree with G1_Extended `DashboardMap` (display modes 0..3, `02 01` + image, `03` + x + y + sprite).
- Chunking: <= 180-byte chunks, `06 | len lo | len hi | sync | 07 | total (u16 LE) | index (u16 LE, 1-based) | chunk`, new sync per packet.
- Pacing (different from the other panes): every packet except the last is sent to the LEFT then to the RIGHT arm with the single-side helpers (sendLeftSide / sendRightSide, which have an ack matcher) but the app does not wait for them; before every 5th packet (index multiple of 5) the app pauses 50 ms [probable]. The LAST packet is sent BothSide and awaited (retryCount 3 if the transfer is a single packet, else 0). Whole transfer limited to 10 s. Command retried up to retryCount = 3 (default) on failure.

### 6.8 exitDashboardWhileBeAwake (opcode 0x56) [certain]
- Frame: `56 06 00 seq 08 00` (6 bytes), seq = a dedicated counter (named "_aiSeqExitDashboard" in the log).
- L first (request, 1000 ms), then R (2000 ms) only if L's reply passed (`byte4 == 0x08`, `byte5 == 0x00`); see [even-ai-transcribe-translate.md](even-ai-transcribe-translate.md), section 3.

## SECTION 7 - Navigation 0x0A

Common frame [certain]: `0A | len lo | len hi | sync | sub | payload`, len = full packet length (u16 LE), sync from the shared counter (`_getSyncId`).

### 7.1 navigateStart (sub 0x00) [certain]
- `0A 06 00 sync 00 01`. BothSide, retryCount 3, timeout 2 s.

### 7.2 navigateSendRouteInfo (sub 0x01) [certain]
- `0A | len | len | sync | 01 | icon (u8) | x (u16 LE) | y (u16 LE) | remainingTime 00 | remainingDistance 00 | roadName 00 | nextDirectionDistance 00 | speed 00`.
- Strings: UTF-8, each terminated by a single 0x00, cut with ellipsis to 23 bytes (remainingTime, remainingDistance, nextDirectionDistance, speed) and 63 bytes (roadName). icon = turn/maneuver icon code; x/y = position fields of the route object (named x and y in the app's model; probably the arrow position on the overview image).
- Skipped when identical to the previous one. BothSide, retryCount 3, timeout 2 s.

### 7.3 navigateHeartBeat (sub 0x04) [certain]
- `0A 06 00 sync 04 n` (n = argument byte supplied by the caller, probable heartbeat counter).
- RIGHT arm only (sendRightSide), timeout 2 s.

### 7.4 navigateExit (sub 0x05) [certain]
- `0A 06 00 sync 05 01`. BothSide, retryCount 5, timeout 3 s.

### 7.5 navigateArrive (sub 0x06) [certain]
- `0A | len | len | sync | 06 | flag | UTF-8 text | 00`. flag = 2 when the navigation is complete (text = localized "navigate_complete"), 1 otherwise (text = localized "destination_reached") [mapping certain, wording of the two cases probable].
- BothSide, retryCount 5, timeout 2 s.

### 7.6 navigateSendDetailsImage (sub 0x02) and navigateSendOverviewImage (sub 0x03) [certain unless marked]
- Image bytes prepared by the navigation module (format not decoded here) are cut into chunks of at most 185 bytes.
- Packet: `0A | len lo | len hi | sync | sub | total (u16 LE) | index (u16 LE, 1-based) | [00 only for the overview image, sub 0x03] | chunk`. So 9-byte header + chunk (details) and 10-byte header + chunk (overview), i.e. at most 194 / 195 bytes. Sync is a per-packet counter (mod 255).
- Pacing: every packet but the last is written with plain writes, LEFT then RIGHT, no ack; a 30 ms pause between packets [probable]. The last packet is sent BothSide and its ack completes the transfer.
- Whole transfer limited to 20 s (overview) / 3 s (details).

### 7.7 Related: quickStartNavigationFailure [probable]
- Not a 0x0A frame: it calls the generic "enter function" command `51 06 00 seq 01 01` (opcode 0x51 = `_sendEnableIntoFunction(1)`), plain write.
