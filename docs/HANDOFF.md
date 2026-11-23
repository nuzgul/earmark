# Handoff — Earmark (voice recorder with bookmarks)

## State (2026-11-23)
- Planning: `docs/PLAN.md`, `docs/ui-premium/PLAN.md`, `docs/design-board.html`, `docs/brand/`.
- Decisions D1–D6 taken with the recommended defaults (Earmark, Codemagic/GitHub macOS for iOS, Pro 5.99 USD one-time, transcription later, iOS backups included, iOS 17.0).
- **Phase 0 done**: Flutter 3.47.7 project, ids `app.earmark.recorder`, tokens/theme/Mona Sans, icon, Pigeon contract, CI.
- **Phase 1 done (Android engine + Record screen)**:
  - Engine (`app/android/app/src/main/kotlin/app/earmark/recorder/engine/`): `RecorderEngine` (AudioRecord 48 kHz mono → MediaCodec AAC-LC 96 kbps → ADTS `audio.aac.part`, frame counter, heartbeat 250 ms, stall watchdog, call silencing via `AudioRecordingCallback`, mic-loss reopen, storage checks), `Journal` (`marks.jsonl`, fsync per mark; `meta.json`), `Finalizer` (ADTS → `audio.m4a` with MediaMuxer, verify, recovery), `Adts`, `PcmSource` (mic + debug-only clock-paced test tone), `RecorderService` (foreground service type microphone; notification with Mark/Pause/Stop always visible), `MarkTileService` (Quick Settings tile).
  - Pause keeps the mic open and drops samples (instant resume, no background mic restart).
  - Bridge: `app/pigeons/engine_api.dart` → start/pause/resume/stop/mark/recover/openAppSettings/useTestTone; events onSnapshot/onMark/onSaved. `mark()` runs on a background task queue.
  - UI (`app/lib/features/record/`): idle (space left, Saved/Recovered strip, microphone-refused card), live (state pill, timer from frames, level line, rolling mark count, last two marks with 2 s marigold outline, Pause/Resume, Stop, Bookmark zone marking on touch-down with haptic), landscape layout, "Checking microphone…" after 1.5 s without heartbeat.
- Verified: `flutter analyze` clean; `flutter test` 10/10 (incl. 5 goldens); JVM engine tests 5/5; integration test (owner's sequence, 3 consecutive runs: marks 10.026/20.053, 10.026/20.010, 10.026/19.989 s; five rapid taps → five marks); emulator manual checks listed in `docs/DEVICE-CHECKS.md`.
- Not verified: anything on a physical phone (`docs/DEVICE-CHECKS.md` A1–A12); iOS never compiled (no Mac); CI never ran (no GitHub remote).

## When the owner says "proceed"
Phase 2 — Library + Playback + Clip on Android (`docs/PLAN.md` §6, §5.5, §5.6, §12):
1. drift DB + FTS5; import `recordings/<id>/meta.json` + `marks.jsonl` (saved and recovered) on launch and on `onSaved`.
2. Library screen (search titles and marks, groups by day, rename, Recently deleted 30 days).
3. Playback (just_audio): waveform from `peaks.bin`, ribbon flags, transport, "Start 3 s before a mark", add/rename/delete marks + Undo.
4. Clip sheet + lossless export (MediaExtractor + MediaMuxer, window 14 s before / 6 s after), share via FileProvider; tests on clip content using the test tone (pitch = 300 Hz + 20 Hz × second) and source SHA-256 unchanged.
5. Settings sheet incl. notification-permission explanation; run device checks A1–A12 on a phone.

## Commands
PowerShell, from `app/`:
- `flutter analyze` · `flutter test` · `flutter test --update-goldens` (after an intended visual change)
- `flutter build apk --debug` → `app/build/app/outputs/flutter-apk/app-debug.apk`
- Regenerate the bridge after editing the contract: `dart run pigeon --input pigeons/engine_api.dart`
- Engine JVM tests: `cd android; .\gradlew :app:testDebugUnitTest`

Git Bash, from `app/` (emulator running, e.g. `Marketing_API35`; the script re-grants the mic after each reinstall):
- `tool/integration_android.sh emulator-5554`
