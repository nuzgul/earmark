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
- Not verified: anything on a physical phone (`docs/DEVICE-CHECKS.md` A1–A12, B1–B7); iOS never compiled (no Mac); CI never ran (no GitHub remote).

## When the owner says "proceed"
Phase 3 — iOS parity (`docs/PLAN.md` §5, §11 R1–R3, §12). Needs a Mac or the macOS CI job (push to GitHub first):
1. Add `swiftOut` to `app/pigeons/engine_api.dart`; Swift engine in `ios/Runner/Engine/` (AVAudioRecorder AAC/CAF or AVAudioEngine + ExtAudioFile after the day-1 spike), same folder layout (`meta.json`, `marks.jsonl`, `peaks.bin`, `audio.m4a`) so the Dart library works unchanged.
2. Interruptions (`AVAudioSession` interruption/route change/media reset), finalize + recovery, clip export (`AVAssetExportSession` passthrough).
3. Live Activity + Dynamic Island Mark (LiveActivityIntent), iOS 18 Control widget, App Group.
4. Info.plist: `NSMicrophoneUsageDescription`, `UIBackgroundModes: audio`, `NSSupportsLiveActivities`, privacy manifest.
5. Same integration tests on the iOS simulator; device checks on an iPhone.
Meanwhile on Android: run device checks A1–A12 and B1–B7 on a phone.

## Commands
PowerShell, from `app/`:
- `flutter analyze` · `flutter test` · `flutter test --update-goldens` (after an intended visual change)
- `flutter build apk --debug` → `app/build/app/outputs/flutter-apk/app-debug.apk`
- Regenerate the bridge after editing the contract: `dart run pigeon --input pigeons/engine_api.dart`
- Engine JVM tests: `cd android; .\gradlew :app:testDebugUnitTest`

Git Bash, from `app/` (emulator running, e.g. `Shared_API35`; the script re-grants the mic after each reinstall):
- `tool/integration_android.sh emulator-5554` (all integration tests) · `TARGET=integration_test/clip_test.dart tool/integration_android.sh emulator-5554` (one file)
