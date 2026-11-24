# Handoff — Earmark (voice recorder with bookmarks)

## State (2026-11-24)
- Planning: `docs/PLAN.md`, `docs/ui-premium/PLAN.md`, `docs/design-board.html`, `docs/brand/`.
- Decisions D1–D6 taken with the recommended defaults (Earmark, Codemagic/GitHub macOS for iOS, Pro 5.99 USD one-time, transcription later, iOS backups included, iOS 17.0).
- **Phase 0 done**: Flutter 3.47.7 project, ids `app.earmark.recorder`, tokens/theme/Mona Sans, icon, Pigeon contract, CI.
- **Phase 1 done (Android engine + Record screen)**: `app/android/app/src/main/kotlin/app/earmark/recorder/engine/` — `RecorderEngine` (AudioRecord → AAC → crash-safe ADTS part, frame-counted marks, heartbeat, stall watchdog, call silencing, mic-loss reopen, storage guards), `Journal`, `Finalizer` (→ `audio.m4a`, recovery), `PcmSource` (mic + debug-only test tone), `RecorderService` (notification Mark/Pause/Stop), `MarkTileService`. Record screen in `app/lib/features/record/`.
- **Phase 2 done (Library, Playback, Clip on Android)**:
  - Data: `app/lib/data/library.dart` — no database (deviation from the plan, recorded in `docs/PLAN.md` §5.6). Each recording folder holds the engine's `meta.json` + `marks.jsonl` (never edited) and the user's edits in `library.json` (title, mark labels, added/deleted marks, trash date; atomic write). In-memory search over titles, mark names and times ("04:32"). Mark numbers never shift after deletes. Recently deleted: 30 days, then purged on load. Pre-roll setting in `files/settings.json`.
  - Screens: `features/library/` (groups Today/Yesterday/This week/Older, search with "Matching marks" first, swipe or ⋯ to delete with Undo, rename, Recently deleted with Restore / Delete now + confirmation), `features/playback/` (waveform from `peaks.bin` with numbered ribbon flags, seek, transport prev/next mark ±10 s, "Start 3 s before a mark", + Mark at the playhead, rename/delete marks with Undo, delete recording → Recently deleted), Clip sheet (14 s before + 6 s after, handles + ±1 s nudges, exact Preview, Share).
  - Engine: `ClipExporter` (MediaExtractor + MediaMuxer, no re-encode, cache/clips, 24 h cleanup), `AudioProbe` (debug-only, for tests). Bridge adds `recordingsRoot`, `exportClip`, `probeAudio`.
  - Player: `just_audio` behind a small `Player` interface (fake in widget tests); pauses when headphones disconnect. Sharing via `share_plus`. Theme now follows the system (light + dark).
  - Release APK permissions: RECORD_AUDIO, FOREGROUND_SERVICE(_MICROPHONE), POST_NOTIFICATIONS only — media3's ACCESS_NETWORK_STATE is removed; no INTERNET.
- Verified (2026-11-24): `flutter analyze` clean; `flutter test` 31/31 (library rules, screens, 12 goldens dark/light/200 %); JVM 5/5; integration on `Shared_API35`: clip test passed twice (clip 20.010 s, start pitch 400.0 Hz = expected second, source bytes unchanged, flag jump with 3 s pre-roll); owner sequence passed (10.005 / 20.010 s) on the same code before the last fixes; release APK permissions checked with aapt2; manual emulator run of Library → Playback → Clip sheet → system share sheet.
- Emulator re-run (2026-11-24, after the last three fixes: Playback waits for the file to open before seeking, bracketed jump check, test mode keeps the screen on): `tool/integration_android.sh emulator-5554` on `Shared_API35` — all tests passed. Owner sequence: mark 1 at 10.026 s, mark 2 at 20.010 s (target ±100 ms), pause held 5 s, duration 20.394 s. Clip test: flag jump landed on the pre-roll point (00:17 for a mark at 20.245 s), clip 20.010 s, start pitch 400.0 Hz = expected, source bytes unchanged.
- **Phase 3 done on the simulator (iOS parity)** — no Mac here; GitHub Actions macOS is the build machine (private repo `nuzgul/earmark`, remote `origin`):
  - Engine `app/ios/Runner/Engine/`: `RecorderEngine` (AVAudioEngine tap → 48 kHz mono → AVAudioConverter AAC → the same ADTS `audio.aac.part` as Android; frame-counted marks plus the time since the newest ~100 ms buffer; Pause/Resume cut inside a buffer; heartbeat + stall watchdog; interruptions → "Paused: call" + auto-resume; route change / media reset → rebuild; storage guards; debug-only test tone), `Journal` (+ `Meta`), `Finalizer` (whole ADTS frames → AVAssetExportSession passthrough → `audio.m4a`; recovery), `ClipExporter` (+ debug `AudioProbe`), `EngineHost` (Pigeon host, mic permission), `LiveActivity`, `EngineApi.g.swift` (Pigeon `swiftOut`).
  - Lock screen: `app/ios/Shared/EarmarkActivity.swift` (ActivityAttributes + Mark / Pause-Resume / Stop LiveActivityIntents + iOS 18 `RecordOrMarkIntent`, compiled into app and extension); widget extension `app/ios/EarmarkWidgets/` (Live Activity + Dynamic Island, "Record or mark" Control). Target added to `Runner.xcodeproj` by hand (checked with a parser: graph complete, files on disk).
  - Info.plist: microphone text, `UIBackgroundModes: audio`, `NSSupportsLiveActivities`; `PrivacyInfo.xcprivacy` (disk space, file timestamps, boot time). Runner Debug now defines `DEBUG` for Swift.
  - CI `ios` job: `flutter build ios --simulator --debug`, then `tool/integration_ios.sh` (both integration tests on a simulator with the test tone).
- Verified on CI (2026-11-24, run 45360561974, iPhone 17 Pro simulator): app + widget extension compile; clip test passed (jump lands on the 3 s pre-roll point, clip 20.000 s, start pitch 400.0 Hz = expected, source unchanged); owner sequence passed (mark 1 at 10.011 s, mark 2 at 20.007 s, pause held 5 s); five taps → five marks. Live Activity created, updated and ended (simulator log); no engine errors. The first run hung when `flutter test` ran both files in one call; `tool/integration_ios.sh` now runs each file alone with a 7-minute limit, saves the app's simulator log and a hang screenshot (artifact `ios-integration-logs`).
- **Phase 4 done (Pro + polish)** (commits dfdcac7 and later):
  - Pro (`lib/features/pro/pro.dart`): `Store` interface, `IapStore` (in_app_purchase, product `earmark_pro`, non-consumable, acknowledged), `NoStore` (tests, unconfigured stores), `Pro` state, Pro sheet (Buy disabled with the reason when not on sale; Restore; "No Pro purchase found" after 8 s). Entitlement = `pro` in settings.json (no server; accepted).
  - Settings sheet (`lib/features/settings/`): pre-roll Off/3/5/10 s, calm screen, quick labels (Pro), Recently deleted, Pro, privacy text, licences. Gear at the top right of idle Record.
  - Record: calm screen (20 s, black, first touch only wakes, Bookmark still marks, off with a screen reader); Bookmark marks on raw pointer-down; hold 450 ms → quick-label arc (Pro), labels saved to the live recording's `library.json`; screen-reader actions "Bookmark as <label>".
  - Playback: "Share several clips" (Pro, `batch_sheet.dart`), speed 1×/1.5×/2×.
  - Audit: `docs/ui-premium/AUDIT-expensive-2026-11-24.md` (fixed: transform-only level line and Record button, haptics on saved/failed, Settings at 200 % text). For the owner: sheets growing from their trigger (B1), deleted-row slide-out (B7).
  - Release manifest: INTERNET removed. It came from Play Billing 9.1's dependency `com.google.android.datatransport:transport-backend-cct` (Google usage logs), not from billing itself (Play Store IPC). Release APK permissions now: RECORD_AUDIO, FOREGROUND_SERVICE(_MICROPHONE), POST_NOTIFICATIONS, com.android.vending.BILLING.
  - Verified (2026-11-24): `flutter analyze` clean; `flutter test` 44/44 (new: `phase4_test.dart`, `expensive_test.dart`, 4 goldens compared on Windows only); release APK builds without INTERNET.
  - Owner's Galaxy S24 FE (Android 17), release build: Settings → Earmark Pro opened Play Billing with no INTERNET permission → "Pro isn't on sale yet", no crash, app alive 10 s later, no crash-buffer entries, no background jobs scheduled.
  - S24, `tool/integration_android.sh R5CX92TT0VB` (test tone): all passed — mark 1 at 10.069 s, mark 2 at 20.032 s, pause held 5 s; clip 20.010 s, start pitch 400.0 Hz, flag jump on the pre-roll point. `flutter test` uninstalled the test app afterwards (Earmark was not on the phone before).
  - CI dfdcac7: iOS simulator passed with the new Bookmark code (mark 1 at 10.013 s, mark 2 at 20.007 s, clip 20.000 s); Android CI failed only on the new goldens (Linux fonts) → now compared on Windows only.
- Not verified: anything on a physical phone (`docs/DEVICE-CHECKS.md` A1–A12, B1–B7, C1–C13): real microphone timing, calls, Bluetooth, lock-screen and Control Center marks, background recording. iOS device builds need an Apple Developer account (signing).

## When the owner says "proceed"
Phases 0–4 are done. Next, in order:
1. Phase 5 (store, `docs/PLAN.md` §12): Play Console app + internal testing track, App Store Connect + TestFlight (Apple Developer Program, 99 USD/year), product `earmark_pro` at the chosen price, listings, screenshots, privacy labels ("Data not collected"), Play foreground-service declaration with a short video. Then test a real Pro purchase on a test track.
2. Device checks on real phones: Android A1–A12, B1–B7 (S24 available); iPhone C1–C13.
3. Owner decisions from the audit: sheets that grow from their trigger (B1), deleted mark rows that slide out (B7).
CI notes: every code push runs Android (Linux) and iOS (macOS, ~8 min). Docs-only pushes skip CI. A private repo has ~200 macOS minutes a month on the free plan; about 65 were used on 2026-11-24.

## Commands
PowerShell, from `app/`:
- `flutter analyze` · `flutter test` · `flutter test --update-goldens` (after an intended visual change)
- `flutter build apk --debug` → `app/build/app/outputs/flutter-apk/app-debug.apk`
- Regenerate the bridge after editing the contract: `dart run pigeon --input pigeons/engine_api.dart`
- Engine JVM tests: `cd android; .\gradlew :app:testDebugUnitTest`

Git Bash on a Mac/CI, from `app/`: `tool/integration_ios.sh` (boots an iPhone simulator, runs each integration test file).

Git Bash, from `app/` (emulator running, e.g. `Shared_API35`; the script re-grants the mic after each reinstall):
- `tool/integration_android.sh emulator-5554` (all integration tests) · `TARGET=integration_test/clip_test.dart tool/integration_android.sh emulator-5554` (one file)
