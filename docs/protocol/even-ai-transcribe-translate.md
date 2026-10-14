# Even AI, transcription, translation, microphone (official Even app 1.6.5)

Source: analysis of the official Even G1 app 1.6.5. Protocol facts only.
Tags: **certain** = seen directly in the app; **probable** = deduced.

## Summary table (details and certainty in the sections below; L then R = R is sent only after L's reply passed the check)
| opcode | sub-cmd | name (app 1.6.5) | side | length | response checked by the app |
|---|---|---|---|---|---|
| 0x52 | 0x01 | setTranscribeStatus | both, L then R (sendBothSide) | 6 | `52`, len > 5, byte3 = seq, byte4 = 01, byte5 = C9 |
| 0x52 | 0x02 | updateTranscribeToOS (text) | L then R | 12 + text | `52`, len > 9, byte4 = 02, byte9 = C9 |
| 0x53 | 0x03 | sendTranscribeHeartBeat | L then R | 6 | `53`, len > 5, byte4 = 03, byte5 = C9 (other = glasses left the feature) |
| 0x09 | 0x01 / 0x02 / 0x03, 0x07 / 0x05 | teleprompter start / run dot / screen / stop | L then R | see [teleprompter.md](teleprompter.md) | status byte 00 = OK |
| 0x24 | 0x06 | pauseTelepromt | L then R | 18 | see [teleprompter.md](teleprompter.md) |
| 0x25 | 0x04 | sendTelepromtHeartBeat | R | 6 | see [teleprompter.md](teleprompter.md) |
| 0x54 | 0x01 | sendAIStatus (isStart, index, status) | L then R | 6, or 8 with isStart | `54`, len > 6, byte4 = 01, byte5 = C9 |
| 0x54 | 0x02 | sendAIAsr (fixed frame) | L then R | 12 | `54`, len > 9, byte4 = 02, byte9 != CA |
| 0x54 | 0x03 | sendAIAnswer (answer text page) | L then R | 12 + text | `54`, len > 9, byte4 = 03, byte9 != CA |
| 0x54 | 0x04 | sendAICmd (index + text) | L then R | 10 + text | `54`, len > 9, byte4 = 04, byte9 != CA |
| 0x55 | 0x05 | sendAIHeartBeat | L then R | 6 | `55`, len > 6, byte4 = 05 (no status byte) |
| 0x56 | 0x08 | exitDashboardWhileBeAwake | L then R | 6 | `56`, len > 5, byte4 = 08, byte5 = 00 |
| 0x0E | value 01 | micOn | one arm (default R) | 2 | byte1 = C9 |
| 0x0E | value 00 | micOff | one arm (R if connected) | 2 | byte1 or byte2 = C9 |
| 0x18 | - | Proto.exit ("exit all func") | one arm, R preferred | 1 | len > 1, byte1 = C9 |
| 0x18 | - | exitFeature | both, L then R | 1 | `18`, len > 1, byte1 = C9 |
| 0x50 | 0x01 | featureRequestStart | R | 6 | `50`, len >= 6, byte4 = 01; byte5 1 = start_now, 2 = wait_close |
| 0x51 | func (1 nav, 2 teleprompter) | quickStartNavigationFailure / quickStartTelepromptFailure | both (native send without side) | 6 | none awaited |
| 0x1C | - | sendTranslatorState (0 start / 1 stop, from, to) | L, then R only if L = C9 | 4 | byte1 = C9 on L; R: any reply |
| 0x0F | - | sendTranslatorSrc (packets) | L then R (requestList) | 7 + up to 193 per packet | each packet: byte1 = C9 or CB |
| 0x0D | - | sendTranslatorDst (packets) | L then R (requestList) | 7 + up to 193 per packet | each packet: byte1 = C9 or CB |
| inbound 0xF5 | 0x17 / 0x18 | long press / release (Even AI) | either arm | >= 2 | - |
| inbound 0xF1 | seq | mic audio (LC3) | mic arm | 202 | - |
No 0x4E frame is built anywhere in app 1.6.5 (replaced by 0x54 sub 0x03).

## Conventions (certain unless noted)

- Transport: Nordic UART, two radios. "L" = left arm, "R" = right arm. "both" = L then R, sequentially (the app awaits the L answer before sending to R in all functions below).
- All multi-byte integers inside frames are little-endian.
- `timeout` = per-attempt wait for the matching response on that side (ms). On timeout the call fails (and the caller may retry).
- Text is UTF-8.
- Timeouts, pauses and retry counts below are the values the app applies (certain). Defaults: request 500 ms, requestRetry 200 ms per attempt, sendOneSide 200 ms, sendBothSide 300 ms.
- BleService.sendBothSide pauses 20 ms before each retry (certain).
- Frames that carry text: `opcode, length_lo, length_hi, seq, subtype, ...` where `length` (LE16) = total frame size including header (and trailer when present).
- Sequence counters (global in the app, taken `% 255` when written to the frame, so values 0..254):
  - transcribe counter (T): used by 0x52 and 0x53, incremented after every 0x52 / 0x53 send.
  - teleprompter counter (P): used by 0x09, 0x24, 0x25, incremented after each send; reset to 0 after a successful final start packet. 0x53 reads it (does not increment it).
  - AI counters: three separate ones (AI answer/status/cmd, AI heartbeat, exit-dashboard).


---
# 1. Transcribe family (opcodes 0x52 / 0x53) - live transcription display

## 0x52 subtype 0x01 - setTranscribeStatus (both arms)
Frame (6 bytes, certain): `52 06 00 T 01 status`
- T = transcribe counter % 255.
- status: 0 = exit, 1 = start normal, 2 = start low-power (app setting "transcribeIsLowPower"), 3 = pause, 4 = resume.
- Send: BleService.sendBothSide in order: L first, R only after L returned a matching reply; timeout 3 s per side; retryCount 5: when the L-then-R sequence fails it is re-sent completely after a 20 ms pause, so at most 6 attempts (certain).
- Response match: byte0 = 0x52, length > 5, byte4 = 0x01, byte3 = T. Success when byte5 = 0xC9 (certain).
- App level: up to 3 additional attempts ("retrySetStatusCount"), then failure.

## 0x53 subtype 0x03 - transcribe heartbeat (L then R)
Frame (6 bytes, certain): `53 06 00 T 03 P` with T = transcribe counter % 255 (then incremented), P = teleprompter counter % 255 (read, not incremented).
- L timeout 500 ms, then R timeout 2000 ms. R is sent only if the L reply has byte5 = 0xC9. (certain)
- Response: byte0 = 0x53, length > 5, byte4 = 0x03. byte5 = 0xC9 -> OK; any other byte5 -> "need exit" (glasses left the feature); timeout -> error.
- App cadence: every 5 s (periodic timer). After 6 consecutive failures the app cancels the timer and exits the feature (certain).

## 0x52 subtype 0x02 - updateTranscribeToOS (text, L then R)
Frame (certain): 12-byte header + UTF-8 text.

| byte | meaning |
|---|---|
| 0 | 0x52 |
| 1-2 | total length LE16 = 12 + utf8 length |
| 3 | T (transcribe counter % 255, incremented after) |
| 4 | 0x02 |
| 5-6 | packetLength = total number of packets, LE16 |
| 7-8 | packetNum = index of this packet, 1-based, LE16 |
| 9 | couldAnimate flag (1/0) |
| 10 | 1 when the "show display pic" flag is false, else 0 (inverted) |
| 11 | 0 (low-light lines, always 0 in app) |

- L timeout 500 ms, then R timeout 1000 ms. R is sent only if the L reply passed the check. (certain)
- Response: byte0 = 0x52, length > 9, byte4 = 0x02, byte9 = 0xC9 (certain).
- Pagination (certain, from the app's transcribe sender): text is first wrapped into display lines. At most 4 lines per screen, sent as at most 2 packets of 2 lines.
  - <= 2 lines: one packet (1/1), lines joined with "\n".
  - > 2 lines: packet 1/2 = lines 0..1, packet 2/2 = lines 2..3 (max 4 lines total), joined with "\n".
  - If the buffer is empty the sender retries up to 3 times.


---
# 2. Teleprompter (opcode 0x09 family, plus 0x24 and 0x25)

Read and checked separately: see [teleprompter.md](teleprompter.md).

# 3. Even AI (opcodes 0x54 / 0x55 / 0x56)

Source functions: Proto.sendAIStatus / sendAIAsr / sendAIAnswer / sendAICmd / sendAIHeartBeat / exitDashboardWhileBeAwake. All are "L then R": the R frame is sent only if the L response passed the check. All use BleManager.request (single attempt per side, no internal retry). (certain)

## Sequence counters (certain)
- `_aiSeq` (one global): shared by 0x54 sub 0x01/0x02/0x03/0x04.
  - sub 0x01 (status): byte 3 = `_aiSeq % 255`, then `_aiSeq += 1` after building the frame.
  - sub 0x02 (asr) and 0x04 (cmd): `_aiSeq += 1` BEFORE building, byte 3 = new value & 0xFF (no % 255: the value is simply truncated to 8 bits).
  - sub 0x03 (answer): `_aiSeq += 1` only when currentPackage == 1 (first packet of an answer), byte 3 = `_aiSeq & 0xFF`; all packets of one answer share the same seq.
- `_aiSeqHeartBeat`: 0x55 only, `% 255`, incremented after each send.
- `_aiSeqExitDashboard`: 0x56 only, `& 0xFF`, incremented after each send.

## 0x54 sub 0x01 - sendAIStatus(isStart, index, status)
Frame (certain): 6 bytes when isStart is false, 8 bytes when isStart is true.
| byte | value |
|---|---|
| 0 | 0x54 |
| 1-2 | total length LE16 (6 or 8) |
| 3 | `_aiSeq % 255` |
| 4 | 0x01 |
| 5 | status (see status table in the flow section) |
| 6 | 0x00 (only when isStart) |
| 7 | index (low byte, only when isStart) |
- L timeout 2000 ms, then R timeout 2000 ms. (certain)
- Response check: byte0 = 0x54, length > 6, byte4 = 0x01, byte5 = 0xC9. Anything else = failure; R is not sent if L fails. (certain)

## 0x54 sub 0x02 - sendAIAsr() (fixed frame, no argument)
Frame (12 bytes, certain): `54 0C 00 S 02 01 00 01 00 01 00 00` (S = `_aiSeq` after increment).
- Same layout as the answer frame below with totalPackage = 1, currentPackage = 1, byte9 = 1, byte10 = 0, and a 1-byte payload 0x00 (byte 11). The app no longer sends the recognised question text: the log prints text = "" and isSpeech = false, isDynamic = true. (certain for bytes; probable that the glasses treat it as "ASR finished, empty text")
- L timeout 1000 ms, then R timeout 2000 ms. (certain)
- Response check: byte0 = 0x54, length > 9, byte4 = 0x02, byte9 != 0xCA (0xCA = failure; anything else, including 0xC9, = success). (certain)

## 0x54 sub 0x03 - sendAIAnswer(text, totalPackage, currentPackage, isOver, isDynamic, progress, {isAutoStream = false})
Frame (certain): 12-byte header + UTF-8 text.
| byte | value |
|---|---|
| 0 | 0x54 |
| 1-2 | total length LE16 = 12 + utf8 length |
| 3 | `_aiSeq & 0xFF` (incremented when currentPackage == 1) |
| 4 | 0x03 |
| 5-6 | totalPackage LE16 |
| 7-8 | currentPackage LE16 (1-based) |
| 9 | flag: if isAutoStream, 1 when isOver else 0; if not isAutoStream, 0 when progress == 255 else 1 |
| 10 | 0x00 |
| 11 | progress (low byte) |
| 12.. | UTF-8 text of this packet |
- isDynamic is only logged, it is not in the frame. (certain)
- L timeout 1000 ms, then R timeout 2000 ms. (certain)
- Response check: byte0 = 0x54, length > 9, byte4 = 0x03, byte9 != 0xCA. (certain)

## 0x54 sub 0x04 - sendAICmd(index, param)
Frame (certain): 10-byte header + UTF-8 param.
| byte | value |
|---|---|
| 0 | 0x54 |
| 1-2 | total length LE16 = 10 + utf8 length |
| 3 | `_aiSeq & 0xFF` (incremented before building) |
| 4 | 0x04 |
| 5-6 | 01 00 (totalPackage = 1) |
| 7-8 | 01 00 (currentPackage = 1) |
| 9 | index (command id, low byte) |
| 10.. | UTF-8 param |
- L timeout 1000 ms, then R timeout 2000 ms. Response: byte0 = 0x54, length > 9, byte4 = 0x04, byte9 != 0xCA. (certain)

## 0x55 sub 0x05 - sendAIHeartBeat()
Frame (6 bytes, certain): `55 06 00 H 05 H` (H = `_aiSeqHeartBeat % 255`, same value twice).
- L timeout 2000 ms, then R timeout 2000 ms. (certain)
- Response check: byte0 = 0x55, length > 6 (so the reply must be at least 7 bytes), byte4 = 0x05. No status byte is checked. (certain)

## 0x56 sub 0x08 - exitDashboardWhileBeAwake()
Frame (6 bytes, certain): `56 06 00 E 08 00` (E = `_aiSeqExitDashboard & 0xFF`). Log text "exitDashboardWhileBeAwake----0x56".
- L timeout 1000 ms, then R timeout 2000 ms. (certain)
- Response check: byte0 = 0x56, length > 5, byte4 = 0x08, byte5 = 0x00 (non-zero = failure). (certain)

## 0x54 sub 0x01 status values seen in the app (certain for the calls, meaning probable)
| status | isStart | index byte | sent by | meaning (probable) |
|---|---|---|---|---|
| 0 | no | - | exitAI() (default value) | end of the AI session (answer timeout, ASR failure, heartbeat lost, unsupported feature) |
| 1 | yes | random "awake prompt" index (EvenAIHelper.getRandomAwakePrompt) | startStreamASR, voice-wake path only | open the AI listening screen; the glasses show their built-in prompt number N |
| 2 | no | - | exitAI(status: 2) just before translate / transcribe / teleprompter / navigation is started by a voice command | AI closes because another feature takes over |
| 3 | no | - | startGlassStreamASR, voice-wake path only, sent just before status 1 | wake / prepare the AI screen |
- The app sends no 0x54 status at all on the touch-bar (long press) path: the glasses open the AI screen themselves. (certain)
- exitAI is wrapped in a retry helper: up to 3 attempts, 100 ms apart (retryTaskWithTimer). (certain)

## 0x54 sub 0x04 command index table (sendAICmd, byte 9) (certain for the index/text pairs)
| index | text sent (UTF-8) | context |
|---|---|---|
| 1 | "Keep Display On until Double Tap." | voice command "always on" |
| 3 / 4 | "Auto Brightness On" / "Manual Brightness Off" | voice command auto brightness on / off |
| 5 | "Brightness Set to N" (N = 1, 100 or computed) | brightness voice commands |
| 6 | "... meters" text | display distance voice command |
| 7 | "Display Height Set to N" | display height voice command |
| 8 / 9 | "Direct Push On" / "Direct Push Off" | voice command |
| 10 / 11 | "Turn on notification" / "Turn off notification" | voice command |
| 13 | "Fail to Start Translate", "Unsupported Language", "Translate not supported for this language.", or localized "window_content_close_feature" | translate cannot start |
| 14 | "Fail to Start Transcribe", "Transcribe not supported for this language.", or the localized close text | transcribe cannot start |
| 15 | "Fail to Start Teleprompt", "No File Detected", or the localized close text | teleprompter cannot start |
| 16 / 17 / 20 | navigation failure texts (reasons home_not_found / office_not_found / app_in_background) | navigation by voice cannot start |
| 18 (0x12) | "I'm having trouble understanding your request." | speech-to-text returned nothing |
| 19 (0x13) | "Network error", or localized "network_error" | LLM stream error, or no network at wake time |
- After an index 13..17/20 or 18 message the app waits 4 s and then sends exitAI (status 0). (certain)
- Normally sent through EvenAIHelper.sendAICommand (1 attempt). The no-network wake path calls Proto.sendAICmd directly, up to 3 tries 50 ms apart. (certain)

# 4. Even AI end-to-end flow (app 1.6.5, class VoiceAssistantCenter) (certain unless noted)

App states: IDLE, COMMAND_DETECTION, COMMAND_LLM_ANALYSING, AI_REPLY_ANSWERING, SINGLE_COMMAND_EXECUTION, CONTINUOUS_COMMAND_STARTING. Wake types: voice (wake word), touchBar (long press).

## 4.1 Touch-bar session (long press)
1. Glasses -> app `F5 17` (either arm; the side is not checked). Handler responseToTouchBarLongPressed: ignored if it comes less than 500 ms after the previous `F5 17`. Then: reset the session, subscribe to inbound `F1` frames and append bytes [2..end] of every frame (LC3 payload; the 2-byte header `F1 seq` is dropped) to an audio buffer; handleWake(touchBar, isTouchBarPressed = true).
2. handleWake: if the phone has no network -> network-error path (4.4). Otherwise state = COMMAND_DETECTION, then startGlassStreamASR(isTouchBarPressed = true, touchBar), which for the touch bar ONLY starts two timers: a 33 s recording watchdog and the AI heartbeat. NO frame is sent: no `0E` (mic on), no `54 01` status. The glasses open the mic and the AI screen by themselves.
3. Glasses stream `F1 seq <200 bytes LC3>` while the touchpad is held.
4. Glasses -> app `F5 18` (release). Handler responseToTouchBarReleased: stops the `F1` subscription at once (audio after the release is discarded), ignored if less than 500 ms after the previous `F5 18`, cancels the 33 s watchdog, then handleTouchBarAIRecordingOver().
   - If no `F5 18` arrives within 33 s of the long press, the watchdog sends Proto.exit (`18`, see section 6) and clears the session.
5. handleTouchBarAIRecordingOver (only when state = COMMAND_DETECTION):
   a. `54 ... 02` fixed ASR frame (the app passes the text "Waiting..." internally, it is NOT transmitted), up to 3 attempts 100 ms apart while the state is COMMAND_DETECTION or COMMAND_LLM_ANALYSING.
   b. The recording goes to disk first, whole and raw, as `even_ai_<timestamp>/record.lc3` (nothing dropped; duration = bytes / 200 / 10 s). It is then converted file to file: LC3 to PCM through the native decoder (method channel `quickNoteLc3ToPcm`, the same decoder as recordings), PCM to WAV, and the WAV goes to the cloud speech-to-text ("azure Audio2Text"). The files are deleted afterwards and the buffer cleared. No noise reduction on this path.
   c. Empty result -> `54 04` index 18 "I'm having trouble understanding your request.", wait 4 s, `54 01` status 0.
   d. Otherwise state = COMMAND_LLM_ANALYSING and the question goes to the LLM (setting "evenllm" = streaming Even LLM, see 4.2.3; otherwise Even AI REST with answer length Compact = evenAiShort, Standard = evenAiMiddle, else evenAi). Bracketed parts "[...]" are removed from the answer. Network failure -> the answer text becomes "Even AI is unable to connect to the network" and is displayed like a normal answer.
   e. state = AI_REPLY_ANSWERING, startSendReply(answer) (4.2).
6. Heartbeat for the whole session: `55` every 5 s (1 s periodic timer, every 5th tick, first one 5 s after the start). 4 consecutive failures -> exitAI (`54 01` status 0). exitAI also stops the heartbeat timer.
7. End of session: 4.3.
- `F5 19` (touchpad double tap "to continue") is NOT used by Even AI; it only drives the onboarding tutorial (Onboarding.touchBarDoubleTapToContinue).
- `F5 00` (double tap = exit) -> App.exitAll(isFromGlass): VoiceAssistantCenter.stopAIbyOS() = local cleanup only, no frame is sent for Even AI (the glasses already left). (The legacy EvenAI service class still sends Proto.exit `18` if it was running; it has no other protocol code left.)
- Old opcode 0x4E ("send AI result"): nothing in app 1.6.5 builds a 0x4E frame. It is replaced by `54 ... 03`. (certain)

## 4.2 Answer display (0x54 sub 0x03)
Text layout: UiUtils.splitTextIntoLines(text, 450.0): the text is split on "\n", then each paragraph is wrapped with Flutter TextPainter, font "GlassFont" size 20, max width 450 px. Pages are built from these lines. In every frame each line is terminated by "\n" (added unless the line already ends with it), lines are concatenated without separator. (certain)

### 4.2.1 Short answer (<= 3 lines) - sendLessThanThreeLines
- One frame, payload = the lines, each terminated by "\n", plus one extra "\n" (e.g. "l1\nl2\n\n"). totalPackage 1, currentPackage 1, isOver = isFinal (true for a complete answer), isDynamic false, progress 255 -> byte 9 = 0, byte 11 = 0xFF. One attempt. (certain)
- If accepted, the answer-ended timer starts (4.3).

### 4.2.2 Long answer (> 3 lines), auto-scroll - scheduleNextRequest / doSendReplyWords
- A "screen" is a window of at most 5 consecutive lines. doSendReplyWords splits the screen text on "\n"; because every line ends with "\n" the split has one extra empty element. If it has fewer than 4 elements (window of 1-2 lines) -> 1 frame (1/1) with everything; otherwise 2 frames with the same seq: packet 1/2 = lines 1-3 of the window, packet 2/2 = lines 4-5 (each re-terminated by "\n"). Consequences: a 3-line window gives packet 2/2 = "\n" only, a 4-line window gives packet 2/2 = "l4\n\n". Packet 2 is sent only if packet 1 was accepted by both arms. (certain)
- isOver flag passed = isFinal, isDynamic = not isFinal (not in the frame), progress (byte 11) = getCurrentProgress(lines, c) = 255 if the answer has <= 5 lines, else min(100, 100 * c / (lines - 4)) with c = index of the current line. byte 9 = 1 whenever progress != 255.
- Timeline: first screen (window starting at line 0, c = 0) 300 ms after the answer is ready. Then a timer with the interval Utils.calculateEvenAIScrollInTerval(auto-scroll speed setting) fires repeatedly; at each tick c += 1 and the window starting at line c-1 is sent (so the first window is shown twice, then the text scrolls ONE line per tick). When c reaches lines - 4 (window = last 5 lines) the screen is sent with isFinal = true and the timer stops. (certain)
- Tap on the touchpad during the answer (`F5 01`): from the R arm = next page, from the L arm = previous page (handled in BleManager by side). Effect: auto-scroll stops for the rest of the session ("manual" mode); c moves by +5 / -5 (clamped to 0; a next page is refused when c + 5 > lines - 1); the window starting at line c is re-sent (5 lines, or what is left). Taps are ignored until the answer display has started (flag couldResponseToSingleTap). If the answer fits in one page (getTotalPages < 2: 0 lines -> 0 pages, 1-4 -> 1, exactly 5 -> 2 (sic), else ceil(n/5)), a tap re-sends the single page padded with "\n\n" (<= 3 lines) or "\n" (4 lines). (certain)

### 4.2.3 Streaming answer (Even LLM) - sendAIReplyWithStream
- Words arrive through StreamBleBuffer (paced word output); every call appends them to the accumulated text, re-wraps all of it and sends:
  - <= 3 lines: like 4.2.1 (isOver = isFinal of this chunk);
  - 4-5 lines: window from line 0;
  - > 5 lines: window of the LAST 5 lines (follow mode), c = lines - 5;
  - the 4-5 line and > 5 line cases pass isAutoStream = true: byte 9 = isOver (1 only on the final chunk) and byte 11 = 100 if the text has more than 6 lines, else 255. The <= 3 line case goes through sendLessThanThreeLines (isAutoStream false): byte 9 = 0, byte 11 = 0xFF, isOver flag only in the call.
- After the final chunk: taps allowed only if the text has more than 5 lines; answer-ended timer starts.
- Stream error -> `54 04` index 19 "Network error".

## 4.3 End of the answer
- After the last screen (or the short answer) the app starts a timer of N seconds, N = setting "even_ai_answer_ended_timeout", default 9 s. When it fires and the state is AI_REPLY_ANSWERING or SINGLE_COMMAND_EXECUTION: exitAI -> `54 01` status 0 (3 attempts, 100 ms apart), heartbeat stopped, state IDLE. (certain)
- No `54 02`, `0E` or `18` is sent at the normal end.

## 4.4 Voice-wake path and no-network path (summary)
- Wake word: when the voice-wakeup feature is on, the app listens to inbound `F1` frames (filter byte 0 = 0xF1) and feeds the decoded audio (native lc3ToPcm) to an on-phone wake-word engine, at most one packet per 20 ms (packets closer than 20 ms are dropped by checkVoicePackageGap). Skipped while teleprompter/transcribe/translate/navigation run or during a touch-bar session. (certain)
- On wake (voice): if the state before waking was IDLE, up to 3 tries of `56 ... 08` (exitDashboardWhileBeAwake), each after a 20 ms pause, until one succeeds; then `54 01` status 3 (isStart false); then `54 01` status 1 isStart true with the random prompt index (up to 3 attempts, 100 ms apart, aborted if the state leaves COMMAND_DETECTION); then the heartbeat. The rest (ASR, answer, end) is the same as the touch-bar path. (certain for frames and order; when exactly the voice recording ends is outside the protocol)
- No network at wake: up to 3 x (`56 ... 08` after 50 ms) until success, then up to 3 x (`54 04` index 19 localized "network_error" after 50 ms) until success. (certain)

# 5. Microphone control (opcode 0x0E) - Proto.micOn / Proto.micOff (certain unless noted)

## 0x0E mic on - micOn(side)
- Frame (2 bytes): `0E 01`.
- Side: L if the app's internal debug flag (Setting singleton, toggled from a debug page) is on AND L is connected; otherwise the side passed by the caller. Every caller passes Proto.lR() = the default side (R when both arms or only R are connected, else L). So in normal use the mic is opened on the RIGHT arm. (certain; meaning of the flag probable)
- One BleManager.request, default timeout 500 ms, no retry inside micOn.
- Reply: success when byte 1 = 0xC9 (reply `0E C9 ...`). A timeout or any other byte = failure.
- The app records the start time of the audio as the midpoint between send time and reply time (used to align audio timestamps).
- Callers: teleprompter AI (voice-follow) mode, Transcribe (start / resume) and Translate when the PHONE microphone is the input (PhoneAudio.micOn -> TransAudio.micOn -> Proto.micOn: the app records on the phone and still sends `0E 01`). NOT Even AI (the glasses open the mic themselves on `F5 17` and stream for the wake word). NOT Translate with the glasses microphone: no call path from GlassAudio to Proto.micOn exists; the app sends `1C 00 <from> <to>` and then waits up to 5 s for the first `F1` frame (MicMonitor.startMonitoring), exiting with "mic start error" if none arrives (certain for the wait; probable that `1C 00` is what opens the mic).

## 0x0E mic off - micOff(side, mode)
- Frame (2 bytes): `0E 00`. (certain)
- Side: same debug-flag rule; callers pass "R" when both arms or only R are connected, else "L".
- Timeout 500 ms.
- The `mode` string ("modeTelepromt", "modeAsr", debug "DebugSavePcm"/"DebugClean"; "modeAsrStableDst" is mapped to "modeAsr") goes only to the native Android layer in the same "send" method-channel call (map keys data/lr/mode); it is NOT transmitted over BLE.
- Callers retry immediately (no pause): teleprompter up to 6 sends, transcribe and translate (TransAudio.closeMic) up to 5, until the reply has 0xC9 at byte 1 OR at byte 2 (both accepted).

## Audio after mic on
- Inbound `F1 seq <200 bytes LC3>` frames (see [transport.md](transport.md) for the codec). Even AI drops the 2-byte header and keeps the payload; the wake-word listener decodes it natively (lc3ToPcm) and accepts at most one packet per 20 ms.

# 6. Feature exit / start coordination (0x18, 0x50, 0x51) (certain unless noted)

## 0x18 - Proto.exit() ("send exit all func")
- Frame (1 byte): `18`.
- Sent to ONE arm: R if R is connected, else L if L is connected, else R. BleManager.requestRetry with its defaults: up to 4 sends (retry 3), 200 ms each, retried only on timeout.
- Success: reply length > 1 and byte 1 = 0xC9 (`18 C9`).
- Used by: Even AI 33 s recording watchdog, App.exitAll (legacy EvenAI path), translate exit, debug pages.

## 0x18 - Proto.exitFeature() (log "exitFeature----0x18-----")
- Same frame `18`, but sent to BOTH arms with BleService.sendBothSide in order (L, then R only after L's reply matched), timeout 300 ms per side (default), retryCount 3: a failed L-then-R sequence is re-sent after a 20 ms pause, at most 4 times.
- Reply filter: byte 0 = 0x18 and length > 1; success: byte 1 = 0xC9.
- Used by FeatureCoordinatorService (below) and by the settings "reset" option.

## 0x50 sub 0x01 - Proto.featureRequestStart() (ask the glasses whether a feature may start)
- Frame (6 bytes): `50 06 00 00 01 01` (byte 3 = 0, no counter; byte 4 = sub 0x01; byte 5 = 0x01).
- Right arm only (BleService.sendRightSide), timeout 2 s.
- Reply filter: byte 0 = 0x50, length >= 6, byte 4 = 0x01. byte 5: 1 = start_now, 2 = wait_close; anything else / timeout = unknown (null).

## Start sequence used before a feature starts (FeatureCoordinatorService.requestStart, retryCount 3)
1. Both arms must be connected (else fail).
2. `39 ... 01` fetchDeviceRunningStatus on L then R (see [settings.md](settings.md)). Unknown status on either arm -> retry.
3. Only if both arms report the same status and it is "none" (0) or "dashboard" (3): `50 06 00 00 01 01` to R.
   - start_now -> the feature starts.
   - wait_close -> `18` to both arms (exitFeature); if it succeeded, wait 100 ms, then the feature starts.
   - no answer -> retry.
4. Retry = wait 20 ms and run the whole sequence again, at most 3 more times (no loading dialog on retries).
5. If the arms report different statuses, or another feature is running, the start is refused (no retry).

## 0x51 - Proto._sendEnableIntoFunction(func) ("quick start failure")
- Frame (6 bytes): `51 06 00 S F 01`. S = own counter (value before increment; the counter wraps to 0 after exceeding 255). F = function: 1 = navigation, 2 = teleprompter. byte 5 = 0x01 always.
- Sent with BleManager.sendData without side (native "send" with no lr: both arms, no reply awaited at Dart level; see [transport.md](transport.md)).
- quickStartNavigationFailure() = F 1: sent when the glasses report the double-tap shortcut (`F5 20`) while the double-tap setting is Navigate (DoubleTapFunction: Dashboard 0, Navigate 1, Translate 2, Teleprompt 3, Transcribe 4, None 5): the app never starts navigation from the glasses, it always answers with this failure frame. (Translate 2 -> app starts translate, Teleprompt 3 -> _launchTelepromptByOS, Transcribe 4 -> app starts transcribe.)
- quickStartTelepromptFailure() = F 2: sent when a teleprompter quick start from the glasses (`F5 20` value 3, or the voice command) cannot start (no script / failure in BleManager._launchTelepromptByOS, VoiceAssistantCenter teleprompter start).
- Meaning of byte 5 = 0x01: probable "cannot enter / failed" (the only value the app sends).

# 7. Translator (opcodes 0x1C, 0x0F, 0x0D) (certain unless noted)

## 0x1C - Proto.sendTranslatorState(a, from, to)
- Frame (4 bytes): `1C a from to`.
  - a = 0 when translation starts (TransSvc.startTrans), 1 when it stops but the translate feature stays open (TransSvc.stopTrans).
  - from / to = glasses language codes, from Glass.languageMap: CN 1, EN 2, JP 3, KR 4, FR 5, DE 6, ES 7, RU 8, NL 9, NO 10, DK 11, SV 12, FI 13, IT 14, AR 15, HI 16, BN 17, HK 18, PL 19, CZ 20, TR 21, PT 22, UK 23, EL 24, HU 25 (the app's from/to language entries carry a "code" key that indexes this map).
- Sent with BleManager.sendBoth(retry 3): L first through requestRetry (up to 4 sends of 250 ms each, retried only on timeout); L timeout -> false; if L's reply byte 1 != 0xC9 the call returns TRUE without sending to R (sic); if L replied 0xC9, R gets the same treatment and the result is "R replied" (no status check on R).

## 0x0F (source text) / 0x0D (translated text) - sendTranslatorSrc / sendTranslatorDst(text, newScreen, pos, {timeoutMs})
Packetisation (TranslatorProto.tansMultiPackListV2(cmd, utf8, newScreen, pos, seq)):
- UTF-8 text cut into chunks of at most 193 bytes; N = number of chunks.
- Each packet: `cmd seq N i newScreen posHi posLo` + chunk (7-byte header, so at most 200 bytes).
  | byte | value |
  |---|---|
  | 0 | 0x0F (sendTranslatorSrc) or 0x0D (sendTranslatorDst) |
  | 1 | seq & 0xFF: one counter for 0x0F and another one for 0x0D, each incremented once per call (all packets of one call share it) |
  | 2 | N, total packets |
  | 3 | i, packet index, 0-based |
  | 4 | newScreen (low byte) |
  | 5-6 | pos as a BIG-endian 16-bit value |
  | 7.. | text chunk |
- There is NO length field.
- Transport: BleManager.requestList, L first, R only if every L packet was accepted. Packets are sent one by one; each needs a reply with byte 1 = 0xC9 or 0xCB, otherwise the list stops (failure). Per-packet timeout: 0x0F -> L 500 ms, R 500 ms; 0x0D -> L 350 ms, R 500 ms, unless the caller passes timeoutMs (start-of-session retry uses 1000 ms).
- An empty text is still sent (only logged).

Text content and fields:
- The displayed text is a list of lines joined with "\r" (carriage return), not "\n". The app wraps lines itself (TextPainter, max width 453 px, font GlassEnFont with GlassCnFont fallback, size 19 probable) and keeps only the last 5 source lines.
- Session start (_sendStartTrans): `0F` with text "\r", newScreen 0, pos 0, then `0D` with "\r", 0, 0 (each retried once with a 1000 ms timeout if it fails). Probable meaning: clear both areas.
- newScreen / pos come from TransHelper.getAnimal(previously sent lines, new lines): (0, 0) when the new text does not continue the previous one (full redraw); (2, P) when it does, P = UTF-8 byte count (line separators not counted) of the lines shared with the previous text, i.e. probably the byte offset where the new part starts, so the glasses can animate only the new part. A forced (2, 0) is used in one case of the source path. (certain: values 0 and 2, P computed by summing UTF-8 lengths; probable: exact line range and glasses-side meaning)

## Translation session sequence (TransSvc)
1. Native speech session started (method channel, outside BLE).
2. `1C 00 <from> <to>`.
3. Audio source started: the glasses mic, unless the user chose the phone mic and the app is in the foreground. Phone mic: the app also sends `0E 01` (section 5). Glasses mic: no frame.
4. `0F "\r"` and `0D "\r"` (clear).
5. The app waits up to 5 s for the first inbound `F1` frame, else "mic start error" and exit. While running, if no decoded voice chunk arrives for 10 s the mic monitor stops.
6. `0F` / `0D` updates as recognition / translation results arrive. The native "eventTranslator" EventChannel delivers {sessionId, src, dst, isEnd} maps to Dart (phone-internal, not BLE); Dart turns them into `0F` / `0D` frames.
7. Stop translating: `1C 01 <from> <to>`.
8. Exit: mic off `0E 00` (up to 5 sends), then, unless the exit came from the glasses, wait 500 ms and `18` (Proto.exit, one arm).
