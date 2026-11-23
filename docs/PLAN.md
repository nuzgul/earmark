# Earmark — product and build plan

Working name **Earmark** (see §10). Version 1 of this plan: 2026-11-23.
Companion files: [design direction](ui-premium/PLAN.md) · [design board](design-board.html) · [logo](brand/logo.svg).

> **One line:** tap once while you talk, find that moment in a second, share just that part.
> **Reference scene:** rehearsing a presentation, at 04:32 you say something worth keeping. Without stopping or looking, you tap Bookmark (or the lock screen, or the Dynamic Island). Later you tap "04:32 · Mark 3", hear the sentence from its start, and share a 20-second clip.

---

## 1. What changed from the original prompt

| Original prompt | This plan | Why |
|---|---|---|
| Android only, Kotlin + Compose | **Android + iOS**, Flutter UI + thin native audio engines (Kotlin, Swift) | You asked for both platforms; see §4 |
| Notification Bookmark action | Plus **iOS Live Activity / Dynamic Island** button, **iOS Control Center / Action Button** control, **Android Quick Settings tile** | Mark from anywhere without unlocking: the main gap in every competitor (§2) |
| 20 s around the bookmark | **14 s before + 6 s after** the tap, still 20 s, both ends adjustable | People tap *after* they hear the good part; a centred window cuts the sentence in half |
| Persist each bookmark | **Crash-proof journal**: audio in a recoverable stream format plus an fsync'd bookmark journal written by the native engine, so a killed app, a dead battery or a crash keeps every second and every mark | "Lost my recording" is the top complaint across recorder apps |
| Search titles and labels | Search shows **matching marks directly** ("04:32 · Budget question") and opens playback at that mark | Finds the moment, not the file |
| Pro: batch export, reusable labels | Same, **one-time purchase**, no subscription, no ads, and the free app has **no internet permission at all** | Trust is a feature; competitors push subscriptions and accounts |

Everything else in the original prompt stays: no sign-up, no server, no paid API, no runtime AI service, three screens, microphone permission on first Record tap, the exact verification sequence (§9).

---

## 2. Competitor research (Nov 2026)

Sources at the end. Claims come from store listings, vendor pages and reviews; verify before quoting them in marketing.

| App | Platforms | Marks while recording? | Share a clip around a mark? | Model | Weak spots we can beat |
|---|---|---|---|---|---|
| Apple Voice Memos | iOS | No markers found; transcripts, layered recording (iOS 18.2), replace/trim | Trim then share the whole memo | Free, built in | No way to flag a moment; edit tools are trimming only |
| Google Recorder | Pixel only | No tap-to-mark; you find moments through the live transcript | Shares transcript selections (audio/video) | Free, Pixel only | Pixel only; no mark from lock screen |
| Samsung Voice Recorder | Galaxy only | Yes, bookmarks | No clip around a bookmark found | Free, Galaxy only | Galaxy only; AI features need Samsung account/Galaxy AI |
| Easy Voice Recorder (Digipom) | Android, iOS | Yes, bookmarks | Not found | Freemium + Pro | Dated UI; no lock-screen mark found |
| Voice Record Pro | iOS | Bookmarks, photos, notes | Not found | Free with ads + IAP | Dated, cluttered UI; ~30% negative review sentiment (aggregator estimate) |
| RecordMark (2025) | iOS 26+ only | Yes: notes, tags, photos, highlight spans pinned to the second; on-device transcription | Not found | Paid / IAP | iOS 26 only; note-taking focus, many controls while recording |
| Just Press Record | iOS, Watch | No markers found | No | Paid | One-tap and Watch are great; no marks |
| Otter, Notta, other AI note takers | Both | Highlights | Some | Subscription, account, cloud | Account + cloud + subscription: the opposite of our promise |

**Gaps nobody fills well (our wedge):**
1. **Marking without looking**: lock screen, Dynamic Island, Control Center, Action Button, notification and Quick Settings, with silent haptic confirmation. Competitors mostly need the app open on screen.
2. **Sharing just the moment**: a clip around a mark, adjusted with both ends, previewed, exported losslessly in seconds. Only Google does something close, and only on Pixel through transcripts.
3. **Reaction-aware timing**: everyone treats a mark as a point; we know you tapped after the good part and start playback and clips before it.
4. **Same quality on both platforms**: today the best mark features are locked to Samsung or Pixel or iOS 26.
5. **Trust**: no account, no network, one-time Pro, and recordings that survive crashes.

---

## 3. What we add beyond competitors (prioritised)

**MVP (v1.0): must ship**
1. **Giant Bookmark target.** While recording, the whole lower ~45% of the screen is the Bookmark button (thumb zone). Pause and Stop sit above it, separated, never adjacent to the target.
2. **Mark from anywhere.** Android: notification action, Quick Settings tile. iOS: Live Activity + Dynamic Island button (iOS 17+), Control Center / Lock Screen / Action Button control (iOS 18+).
3. **Silent confirmation.** A haptic tick plus the visual ribbon drop, no sound (a beep would be recorded into your audio). A screen reader announces "Mark 3 at 4 minutes 32 seconds".
4. **Exact times.** Mark position = audio frames actually encoded at the moment of the tap. Paused time cannot leak in, by construction. Every tap appends a new mark; nothing is overwritten.
5. **Crash-proof recording** with automatic recovery on next launch ("Recovered 23:41 from an interrupted recording, 4 marks kept").
6. **Honest state.** The UI shows only what the engine reports through a heartbeat; "Recording" disappears within 1.5 s if frames stop. Calls and microphone takeover → "Paused: call" with a system marker; optional auto-resume.
7. **"Start 3 s before" playback** (setting: 0 / 3 / 5 / 10 s), previous/next mark buttons, 1× / 1.5× / 2× speed.
8. **Clip sheet**: 14 s before + 6 s after, drag both handles or nudge ±1 s (accessible), exact preview of the range, lossless export, share sheet. Edge-aware near start and end; whole recording if shorter than the clip.
9. **Search that lands on the moment**, across titles and mark labels.
10. **Readable default titles**: "Tuesday morning", "Tuesday morning 2".
11. **Calm mode**: after 20 s without touches the recording screen dims to an OLED-friendly black with only timer, mark count and the Bookmark zone (a touch restores it; the first touch still marks).
12. **Privacy by architecture**: Android build without the `INTERNET` permission (verify that Play Billing works without it, §11 R6); iOS privacy manifest "Data Not Collected".

**v1.1: differentiators after launch**
13. **Chapters export**: share the whole recording as an `.m4a` with marks embedded as chapters (they show up in Apple Podcasts/most players), plus "Copy marks as text" (`04:32 Budget question`).
14. **Headset mark (spike first)**: a single press on wired/Bluetooth earbuds marks. Feasibility differs per OS (§11 R4); ship only where reliable.
15. **Watch remote**: Apple Watch and Wear OS one-button Mark with wrist haptic.
16. **Quick labels (Pro)**: long-press Bookmark opens a thumb arc of up to 4 of your reusable labels (Idea, To-do, Quote, Question).
17. **Android 16 Live Updates**: promoted ongoing notification / status-bar chip with the timer.

**Later (owner decision required)**
18. **On-device transcript of the 20 s around each mark** (iOS 26 SpeechAnalyzer, Android on-device recogniser) so search finds words you never typed. No cloud, no runtime fee, but device support varies, so it ships as optional.
19. **Audiogram clip**: export the clip as a short video (waveform + title) for apps that do not accept audio files.

**Deliberately not doing:** cloud sync, accounts, AI summaries, editing/cutting the source recording, ads, subscriptions.

---

## 4. Technology decision

**Choice: Flutter for the UI and app logic, plus a small native audio engine per platform (Kotlin on Android, Swift on iOS), connected with Pigeon (type-safe generated channels).**

| Option | UI on both | Native audio and system surfaces | Verdict |
|---|---|---|---|
| **Flutter + native engines** | One custom UI rendered identically (Impeller), strong for a custom waveform/timeline | Engine, foreground service, Live Activity, widgets in Kotlin/Swift; Pigeon bridge | **Chosen**: mature on iOS, one design system, native where it matters |
| Kotlin Multiplatform + Compose Multiplatform | Compose on iOS has been stable since 2025 but is younger on iOS (text input, accessibility, scrolling feel) | Kotlin shared logic; iOS still needs Swift for ActivityKit/WidgetKit | Strong alternative if you prefer Kotlin everywhere |
| React Native / Expo | Good | Same native modules needed; more bridging glue | No advantage here |
| Two native apps | Best per platform | Best | Double UI work; ruled out for one developer |

The deciding fact: **the audio engine must be native on any stack.** A microphone foreground service, audio-session interruptions, Live Activities, Control Center controls and lossless trimming are platform APIs. So the question is only where the UI lives, and Flutter gives one premium UI with the most mature iOS story.

**Versions (pin at kickoff):** current stable Flutter and Dart 3; Android `minSdk 26`, `targetSdk 36`, Kotlin 2.x; iOS deployment target **17.0** (interactive Live Activities), Control Center control gated to iOS 18; Swift 6, Xcode 26.

**Packages (kept minimal):**
- `drift` (SQLite with FTS5 search), `path_provider`
- `just_audio` + `audio_session` for playback and exact clip preview (`ClippingAudioSource`)
- `share_plus`, `in_app_purchase` (Pro)
- `pigeon` (dev) for the engine API
- State: Flutter's own `ChangeNotifier` / `ValueListenableBuilder`; navigation: plain `Navigator` (three screens). No state-management or routing framework until one is needed.
- **Not used:** `ffmpeg_kit_flutter` (retired January 2025). Trimming uses the platform's own lossless APIs (§5.5).

**Build machines:** you are on Windows. Android builds locally. **iOS needs macOS**: a Mac, or CI on GitHub Actions macOS runners or Codemagic. Installing on a real iPhone, Live Activities and TestFlight need an Apple Developer Program membership (99 USD/year).

---

## 5. Architecture

```
Flutter (Dart)                                     Native engine (one per OS)
──────────────────────────────────────            ─────────────────────────────────────────
RecordScreen  LibraryScreen  PlaybackScreen        RecorderEngine  (owns the session)
   │               │             │                  ├─ capture: AudioRecord→MediaCodec AAC (Android)
   └── EngineClient (Pigeon) ◄── events ───────────┤            AVAudioRecorder AAC/CAF (iOS)
        start/pause/resume/stop/mark               ├─ SessionJournal  (marks.jsonl, fsync each mark)
   ── Repository (drift SQLite + FTS5)             ├─ PeaksWriter     (waveform levels sidecar)
   ── Player (just_audio)                          ├─ InterruptionMonitor (calls, mic loss, storage)
   ── ClipController → engine.exportClip()          ├─ Finalizer (remux to .m4a) + Recovery
                                                     ├─ ClipExporter (lossless cut)
                                                     └─ Surfaces: FGS notification, QS tile (Android)
                                                                  Live Activity, Control widget (iOS)
```

**Source of truth.** While a session runs, the **native engine** owns it: audio file, mark journal, state. This is what lets a notification or Dynamic Island mark work when the Flutter UI is not running. Dart's SQLite database is the library index; finished and recovered sessions are imported into it in one transaction.

### 5.1 Files per recording
```
<app documents>/recordings/<uuid>/
  audio.aac.part   Android, while recording (ADTS stream, readable up to the last frame after a crash)
  audio.caf        iOS, while recording (CAF tolerates an unfinished file)
  audio.m4a        final file after Stop (remuxed, no re-encode)
  marks.jsonl      one line per mark: {"id","pos_frames","sample_rate","created_at","source"}
  peaks.bin        one level per 50 ms, for an instant waveform
```
Default quality: AAC-LC mono 48 kHz, 96 kbps ≈ 43 MB/hour. Settings: Speech (64 kbps), Standard (96), High (160, stereo where the mic supports it).

### 5.2 Timing model (the core guarantee)
- The engine counts **PCM frames handed to the encoder**. A mark stores `pos_frames` at the instant the engine receives it. `positionMs = pos_frames * 1000 / sampleRate`.
- **Pause** stops reading the microphone, so the counter stops and paused time is excluded by construction. A mark during pause lands on the pause point.
- iOS with `AVAudioRecorder`: `currentTime` reports recorded time and excludes pauses; a spike in Phase 3 confirms its precision against the frame count (fallback: `AVAudioEngine` tap + `ExtAudioFile`).
- **Rapid taps**: each tap appends a new line with its own id; no debounce, no overwrite. Two taps under 400 ms apart stay two marks; the UI shows "Mark 4, Mark 5".
- Bridge latency (Pigeon or a notification broadcast) is a few milliseconds, well under one AAC frame block (21 ms).

### 5.3 Session lifecycle
`idle → starting → recording ⇄ paused → finalizing → saved`, plus `interrupted(reason)` and `recovering`.
- **Heartbeat**: the engine emits `{state, frames, level, marks}` every 250 ms. If the UI receives no heartbeat for 1.5 s while "recording", it shows "Checking microphone…" and asks the engine for its state. Nothing displays "Recording" unless frames are advancing.
- **Stop** = finalize: Android remuxes ADTS → `.m4a` with `MediaMuxer`; iOS exports CAF → `.m4a` with an `AVAssetExportSession` passthrough. Verify the file is readable, then delete the `.part`/`.caf`, import into the database, show "Saved".
- **Recovery on launch**: any folder with a `.part`/`.caf` and no live session → finalize what exists, import the marks, and show a "Recovered" banner on the recording.

### 5.4 Interruptions and edge cases
| Event | Android | iOS | User sees |
|---|---|---|---|
| Incoming call / mic taken | `AudioManager.registerAudioRecordingCallback` → `isClientSilenced` (API 29+), plus a zero-signal watchdog | `AVAudioSession.interruptionNotification` | "Paused: call" + a grey system marker; auto-resume if enabled, else Resume button |
| Bluetooth mic disconnects | `AudioDeviceCallback` → continue on built-in mic | `routeChangeNotification` | Toast "Switched to phone microphone" + system marker |
| Media services reset | — | `mediaServicesWereResetNotification` → finalize and start a new part | "Recording continued in a new part" |
| Low storage | `StatFs` before start (needs ≥ 100 MB) and every 15 s | `volumeAvailableCapacityForImportantUsage` | Banner at < 150 MB; graceful stop and save at < 50 MB |
| Process killed / battery dies | Journal + ADTS survive; recovery on launch | CAF + journal survive; recovery on launch | "Recovered" banner |
| Rotation / UI rebuilt | Engine state lives outside widgets; UI re-subscribes | same | Nothing is lost |
| Aggressive OEM battery savers | Foreground service + one-time tip linking battery settings when a kill is detected | — | Tip after the first detected kill |

### 5.5 Clip export (lossless)
- Android: `MediaExtractor` + `MediaMuxer` copy the AAC samples between start and end into a new `.m4a` (accurate to one AAC frame, ~21 ms). No re-encode, ~instant even for an hour-long file.
- iOS: `AVAssetExportSession(preset: Passthrough)` with `timeRange` → `.m4a`.
- Output goes to a cache "share" folder that is cleared after 24 h; shared through `FileProvider` (Android) and the share sheet (iOS). The source file is opened read-only, and its hash is checked in tests.
- File name: `Pitch rehearsal — Mark 3 (04-18 to 04-38).m4a`.
- **Window rule**: default `[t − 14 s, t + 6 s]`; if `start < 0`, shift right; if `end > duration`, shift left; if the recording is shorter than 20 s, use the whole recording. Minimum clip 1 s; maximum 10 min (free and Pro).

### 5.6 Data model (drift / SQLite)
```
recordings(id TEXT PK, title, created_at, duration_ms, sample_rate, codec, bytes,
           status[saved|recovered|deleted], deleted_at NULL, folder)
marks(id TEXT PK, recording_id FK, pos_ms, label NULL, auto_index, source[app|notification|tile|live_activity|control|watch|system],
      kind[user|system], created_at, deleted_at NULL)
label_presets(id, text, sort)                         -- Pro
search_fts USING fts5(recording_id, mark_id, text)    -- titles + labels + "Mark N"
```
Deleted marks: soft-delete with Undo for 5 s, then purged. Deleted recordings: moved to **Recently deleted** for 30 days (files kept), then removed.

### 5.7 Permissions and system declarations
- Microphone: requested on the first Record tap only. Denied → an inline card ("Earmark needs the microphone to record. Your library still works.") with an **Open Settings** button; "don't ask again" handled.
- Android: `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS` (asked when recording starts, explained if refused: recording still works, the notification Mark button needs it). The service is started only from a visible activity (Android 14+ while-in-use rule). Play Console foreground-service declaration with a short demo video.
- iOS: `NSMicrophoneUsageDescription`, `UIBackgroundModes: audio`, `NSSupportsLiveActivities`, App Group shared with the widget extension, privacy manifest.
- Backups: Android `allowBackup=false` (audio is too big for Auto Backup); iOS files are included in the user's own device backup (owner decision D5).

### 5.8 Repository layout
```
app/                       Flutter project (name: earmark)
  lib/app/                 theme tokens, app shell
  lib/features/record|library|playback|clip|pro/
  lib/data/                drift database, repository, search
  lib/engine/              Pigeon-generated API + EngineClient
  pigeons/engine_api.dart
  android/app/src/main/kotlin/.../engine/   RecorderService, Capture, Journal, Peaks, Finalizer, ClipExporter, MarkTile
  ios/Runner/Engine/                         RecorderEngine.swift, ClipExporter.swift, Journal.swift
  ios/EarmarkWidgets/                        Live Activity, Control widget, App Intents
  test/  integration_test/
docs/                      this plan, design, handoff
```

---

## 6. Screens and behaviour

Navigation: **Record is home.** Library opens from the top-left; Playback is pushed from Library or from "last recording". Clip, rename and Pro are bottom sheets, not screens.

**Record, idle.** Large timer `00:00` (dimmed), storage left ("38 h of space left"), last recording strip (tap → Playback), one 132 dp Record button in the thumb zone.

**Record, recording.** Top: state pill (red dot + "Recording" / "Paused" / "Paused: call") and mark count. Timer 76 sp tabular. A thin level line (smoothed, 20 fps, no bouncing bars) in place of a busy meter. The last two marks as rows; the newest gets a marigold outline for 2 s. Control row: **Pause/Resume** left, **Stop** right (56 dp, 24 dp gap). Bottom ~45%: the **Bookmark** zone (≥ 200 dp tall, full width, marigold). Portrait-first; landscape puts the Bookmark zone on the right half.

**Library.** Large title, search field "Search titles and marks", groups Today / Yesterday / This week / Older. Row: title, start time · duration, marigold mark-count badge. Search results show **Matching marks** first (time, label with the match highlighted, recording name), then recordings. Swipe a row → Rename / Delete (Delete → Recently deleted + Undo). An empty state teaches the one gesture.

**Playback.** Title (tap to rename), date · duration · marks. Waveform from `peaks.bin` with **ribbon flags** numbered at each mark; tap a flag = jump (with pre-roll). Transport: previous mark, −10 s, play/pause (72 dp), +10 s, next mark. Toggle "Start 3 s before a mark". Mark list rows: time, label, **Share clip** chip, row menu (Rename, Delete mark). Sticky bottom button "+ Mark at 04:29" (current position). **Deleting a mark** = row slides out + "Mark deleted · Undo". **Deleting the recording** is only in the top-right menu, in error colour, with a sheet that names the recording, its length and its marks count.

**Clip sheet.** Title "Share clip · {label}", range readout `04:18 → 04:38 · 20.0 s`, zoomed waveform (±60 s) with two handles (48 dp hit areas), ±1 s nudge buttons for each end, **Preview** (plays exactly the range) and **Share**. While exporting, the Share button shows progress in place; success = the system share sheet.

**Pro sheet.** What Pro adds, price, Buy, Restore. If the store is not configured: "Pro is coming soon" and a disabled Buy button with that reason in text.

**Settings (sheet from Record):** theme, quality, clip length split, pre-roll seconds, auto-resume after calls, calm mode, Recently deleted, Pro, privacy statement, licences.

---

## 7. Design direction (summary)

Full direction, tokens and motion: [ui-premium/PLAN.md](ui-premium/PLAN.md). Visual board: [design-board.html](design-board.html).

- **Idea: "the highlighter in a dark studio."** Warm carbon neutrals carry 90% of the screen; **marigold `#FFC23D` belongs to marks only** (Bookmark zone, ribbon flags, mark badges); red only for live capture. You learn the colour code in one session: yellow = a moment you kept.
- **Numbers are the hero**: tabular timer and timestamps, tight tracking.
- **Logo**: the loudest bar of a sound wave is a bookmark ribbon hanging from the top edge (`docs/brand/logo.svg`, mono version for themed/notification icons).
- **Motion**: subtle and tied to real events. Touch-down feedback < 100 ms; the ribbon drops from the Bookmark zone into the marks list (250 ms); the count rolls; haptic on the same frame. Reduced motion → instant change or a 150 ms fade.

---

## 8. Monetisation

- **Free forever:** recording, unlimited length and recordings, marks from every surface, playback, search, sharing one clip at a time, recovery.
- **Pro, one-time** (suggested 5.99 USD; owner decides): batch clip export (select marks → export all → share multiple files or one zip), reusable labels with the long-press arc, chapters export, alternative app icons.
- Product id `earmark_pro` (non-consumable) on both stores. Without store credentials the Buy button stays disabled with a reason, and the free app is complete.
- No ads, no subscription, no account. That is the marketing line.

---

## 9. Verification plan

**Automated (every commit, CI):**
- Dart unit tests: clip-window rule (start, middle, end, short recording), default titles, search ranking, mark numbering after deletes.
- Kotlin JVM tests: frame→ms mapping, journal parse with a truncated last line, window clamps.
- Android instrumented tests with a **test audio source** (the engine's second capture source, used only in tests): a tone whose pitch encodes the second (300 Hz + 20 Hz × second). This lets a test prove a clip's **content**: the clip from 10 s must start with the 500 Hz tone.
- Flutter `integration_test` on an emulator runs the **owner's sequence through the real UI**: record 10 s → Bookmark → Pause 5 s → Resume 10 s → Bookmark → Stop. Expect marks at 10.0 s and 20.0 s (± 0.1 s), duration 20 s (± 0.1 s). Replay both marks (player position checks). Export a clip around mark 2 and check: duration, playable (`MediaExtractor` opens it), pitch at clip start, and the source file's SHA-256 unchanged.
- Edge cases: mark at 0.5 s and at duration − 0.5 s in a 6 s recording → clip = whole recording; rapid 5 taps in 1 s → 5 marks; process kill mid-recording → recovery test.
- iOS: XCTest for the engine on the simulator (macOS CI), same sequence via `integration_test`.
- `flutter analyze`, golden tests of the three screens (dark, light, text scale 1.5 and 2.0).

**Needs a physical phone (checklist kept in `docs/DEVICE-CHECKS.md`):** screen-locked recording 10+ min, notification and QS-tile marks while locked, incoming call, Bluetooth mic loss, low storage, OEM battery killer (Samsung/Xiaomi), Live Activity + Dynamic Island mark, Control Center/Action Button, VoiceOver/TalkBack pass, 1-hour recording finalize time.

**Release artefacts:** debug APK at `app/build/app/outputs/flutter-apk/app-debug.apk`; iOS through TestFlight.

---

## 10. Name, logo, store identity

- **Earmark** (recommended): "to mark for later" + ear. Known clash: *Earmark CPE* (an accounting podcast app). Run a trademark and store search before committing.
- Alternatives: **Dogear** (dog-ear a page + ear), **Marklet**, **Pinpoint Recorder**.
- Store subtitle: "Voice recorder with bookmarks". Keywords: bookmark recorder, mark moments, lecture recorder, share clip.
- Screenshots tell the reference scene in four frames: Record → Mark from lock screen → Find "04:32" → Share clip.

---

## 11. Risks and spikes

| # | Risk | Mitigation |
|---|---|---|
| R1 | Live Activity updates are throttled for background apps | Timer drawn with `Text(timerInterval:)` (no updates needed); update only on mark/pause/resume; mark itself runs as a `LiveActivityIntent` in the app process. Spike in Phase 3 |
| R2 | Starting a recording from the Action Button / Control Center while the app is closed | iOS 18 `AudioRecordingIntent` (requires a Live Activity); fallback: the control opens the app and starts. Spike |
| R3 | iOS `AVAudioRecorder` + CAF recovery after a kill | Spike day 1 of Phase 3; fallback `AVAudioEngine` + `ExtAudioFile` |
| R4 | Headset button mark: buttons route to the last media app | v1.1 spike; ship per platform only if reliable |
| R5 | OEM background killers | Foreground service, journal and recovery, a battery-settings tip |
| R6 | Play Billing with no `INTERNET` permission | Verify in Phase 4; if it is needed, keep it and say so honestly in the privacy text |
| R7 | Play foreground-service review | Declaration + demo video prepared in Phase 5 |
| R8 | No Mac on hand | Codemagic / GitHub macOS runners for build; a borrowed or cloud Mac for device debugging |

---

## 12. Roadmap and acceptance criteria

Estimates assume one developer with Claude; adjust after Phase 1.

| Phase | Scope | Done when |
|---|---|---|
| **0 · Setup** (1–2 d) | Decisions D1–D6, Flutter project, CI (Android), tokens + fonts + icon, Pigeon API skeleton | `flutter build apk --debug` in CI; theme renders in a golden test |
| **1 · Android engine + Record** (4–6 d) | Capture + AAC ADTS, frame counter, journal, peaks, pause/resume, foreground service + notification (Mark/Pause/Stop), QS tile, permission flow, heartbeat state, interruptions, low storage, finalize, recovery | The owner's sequence passes in `integration_test`; kill-and-recover test passes; notification Mark verified on a phone |
| **2 · Library + Playback + Clip (Android)** (4–6 d) | drift DB + FTS, Library, search hits, rename, Recently deleted, Playback with flags and list, pre-roll, add/rename/delete mark + Undo, Clip sheet, lossless export, share | Clip content/duration/source-hash tests pass; **debug APK delivered**; device checklist Android part done |
| **3 · iOS parity** (5–8 d, needs Mac/CI) | Swift engine, interruptions, finalize/recovery, clip export, Live Activity + Dynamic Island Mark, Control widget, App Group | Same integration test on the iOS simulator; Live Activity mark on an iPhone; TestFlight build |
| **4 · Pro + polish** (3–5 d) | in_app_purchase, batch export, label presets + long-press arc, calm mode, accessibility pass, "make it expensive" checks (touch-down < 100 ms, haptic on the frame, reduced motion) | Pro purchase works in test tracks or stays disabled with a reason; a11y and motion checks recorded in `docs/ui-premium/` |
| **5 · Store** (2–3 d) | Store listing, screenshots, privacy labels, FGS declaration, release builds | Internal testing track + TestFlight live; owner approves release |
| **v1.1** | Chapters export, Watch/Wear, headset spike, Android 16 Live Updates | Each item behind its own acceptance test |

---

## 13. Decisions needed from the owner

| # | Decision | Recommendation |
|---|---|---|
| D1 | App name | Earmark, after a trademark/store search |
| D2 | iOS build route | Codemagic (free tier) or a Mac; Apple Developer account for device tests |
| D3 | Pro price | 5.99 USD one-time |
| D4 | On-device transcription of marks (§3 #18) | Later, optional |
| D5 | Include recordings in the iOS device backup | Yes (the user's own encrypted backup); say so in the privacy text |
| D6 | Minimum iOS | 17.0 |

---

## 14. Execution brief for the build session

> Build **Earmark** per `docs/PLAN.md` and `docs/ui-premium/PLAN.md` in `app/`. Flutter UI; native Kotlin and Swift audio engines over Pigeon; no network, no account, no paid API. Phases 0→5 in order; after each phase run `flutter analyze`, `flutter test`, the Android integration test and the build, update `docs/HANDOFF.md`, and commit. Marks are frame-counted in the native engine and journaled with fsync; the UI shows only heartbeat-confirmed state. Clip = 14 s before + 6 s after, lossless export. Verify the owner's sequence (10 s, mark, pause 5 s, resume 10 s, mark → 10.0 s and 20.0 s) through the real UI, the end-of-recording mark, and clip content/duration/source integrity; list everything that needs a physical phone. Describe features as complete only when they work through the normal UI.

---

## Sources
- [Global Delight: voice recording apps with a bookmarking feature](https://blog.globaldelight.com/audion/voice-recording-apps-with-a-bookmarking-feature)
- [RecordMark on the App Store](https://apps.apple.com/us/app/-/id6751431939) · [RecordMark support](https://sarmacodes.github.io/docs/RecordMark_Support.html) · [Product Hunt](https://www.producthunt.com/products/recordmark-annotate-audio)
- [Voice Record Pro reviews (Justuseapp aggregate)](https://justuseapp.com/en/app/546983235/voice-record-pro/reviews)
- [Tom's Guide: built-in recorder apps compared](https://www.tomsguide.com/phones/i-needed-help-writing-after-breaking-my-arm-so-i-put-the-built-in-voice-recorder-apps-on-top-phones-to-the-test) · [Samsung vs Pixel recorder](https://www.tomsguide.com/phones/android-phones/samsung-galaxy-s24-vs-google-pixel-voice-recorder-app-showdown-whos-got-the-better-ai-features)
- [iGeeksBlog: Voice Memos in iOS 26](https://www.igeeksblog.com/how-to-use-voice-memos-on-iphone-ipad/)
- [Riverside: best voice recorder apps 2026](https://riverside.com/blog/best-voice-recorder-app)
- [FFmpegKit retirement](https://www.itpathsolutions.com/ffmpegkit-shutdown-what-to-do-next)
- Apple Developer Forums: [AudioRecordingIntent from background](https://developer.apple.com/forums/thread/815725), [Live Activity updates during background audio](https://developer.apple.com/forums/thread/822999), [audio controls with ActivityKit](https://developer.apple.com/forums/thread/716882)
