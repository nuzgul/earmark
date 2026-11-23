# Handoff — Earmark (voice recorder with bookmarks)

## State (2026-11-23)
- Planning: `docs/PLAN.md`, `docs/ui-premium/PLAN.md`, `docs/design-board.html`, `docs/brand/`.
- Decisions D1–D6 taken with the recommended defaults (Earmark, Codemagic/GitHub macOS for iOS, Pro 5.99 USD one-time, transcription later, iOS backups included, iOS 17.0).
- **Phase 0 done** (`app/`): Flutter 3.47.7 project, ids `app.earmark.recorder` (Android + iOS), Android minSdk 26 / target 36, iOS 17.0, backup off, carbon launch screen, adaptive + themed icon (vector) and iOS 1024 icon, Mona Sans bundled, design tokens + theme + `PressableScale`, Pigeon engine contract (`app/pigeons/engine_api.dart`) with a Phase 0 Kotlin stub, idle Record screen, tests + goldens, CI (`.github/workflows/ci.yml`: Android analyze/test/APK, iOS compile check).
- Verified: `flutter analyze` clean, `flutter test` 3/3, `flutter build apk --debug` OK, emulator run (screen renders, tap Record reaches the Kotlin stub and shows its message, launcher icon correct).
- Not verified: CI has never run (no GitHub remote yet); iOS has never been compiled (needs the macOS CI job or a Mac).

## When the owner says "proceed"
Phase 1 — Android engine + Record (`docs/PLAN.md` §5, §12):
1. `app/android/.../engine/`: `RecorderService` (foreground service, type microphone, notification with Mark/Pause/Stop), capture `AudioRecord` 48 kHz mono → `MediaCodec` AAC → ADTS `audio.aac.part`, frame counter, `marks.jsonl` journal (fsync per mark), `peaks.bin`, heartbeat every 250 ms through `RecorderEvents`, finalize to `.m4a` with `MediaMuxer`, recovery on launch, interruptions (`AudioRecordingCallback`, device callback, storage).
2. Replace `PendingEngine` in `MainActivity.kt` with the real engine; add manifest permissions (`RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`) and the service.
3. Recording UI: state pill, timer from `positionMs`, `LevelLine`, Bookmark zone (mark on touch-down), last marks, Pause/Stop, permission-denied card.
4. Test audio source + `integration_test` for the owner's sequence (10 s, mark, pause 5 s, resume 10 s, mark → 10.0 s and 20.0 s ±0.1 s).

## Commands (PowerShell, from `app/`)
- `flutter analyze` · `flutter test` · `flutter test --update-goldens` (after an intended visual change)
- `flutter build apk --debug` → `app/build/app/outputs/flutter-apk/app-debug.apk`
- Regenerate the bridge after editing the contract: `dart run pigeon --input pigeons/engine_api.dart`
