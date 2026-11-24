# Earmark — project rules

- Plan: `docs/PLAN.md` (source of truth); design: `docs/ui-premium/PLAN.md`; resume from `docs/HANDOFF.md`.
- Stack: Flutter UI in `app/`; native audio engines in Kotlin (`android/.../engine/`) and Swift (`ios/Runner/Engine/`), bridged with Pigeon.
- Hard rules: no network, account, server, paid API or runtime AI service. Audio leaves the device only through user export/share.
- Marks are frame-counted and journaled (fsync) by the native engine; the UI shows only heartbeat-confirmed recording state.
- Marigold is for marks only; red only for live capture.
- iOS builds need macOS (Mac or CI); the owner works on Windows.
- Commands (from `app/`): `flutter analyze`, `flutter test` (goldens are rendered on Windows; CI skips the `golden` tag), `flutter build apk --debug`, `dart run pigeon --input pigeons/engine_api.dart`, engine JVM tests `cd android && ./gradlew :app:testDebugUnitTest`, integration on an emulator `tool/integration_android.sh emulator-5554` (Git Bash; uses the debug-only test tone, never the host mic); iOS integration runs on CI only (`tool/integration_ios.sh` on the macOS job; private repo `nuzgul/earmark`, docs-only pushes skip CI).
- App id: `app.earmark.recorder` on both platforms.
