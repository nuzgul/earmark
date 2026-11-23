# Earmark — project rules

- Plan: `docs/PLAN.md` (source of truth); design: `docs/ui-premium/PLAN.md`; resume from `docs/HANDOFF.md`.
- Stack: Flutter UI in `app/`; native audio engines in Kotlin (`android/.../engine/`) and Swift (`ios/Runner/Engine/`), bridged with Pigeon.
- Hard rules: no network, account, server, paid API or runtime AI service. Audio leaves the device only through user export/share.
- Marks are frame-counted and journaled (fsync) by the native engine; the UI shows only heartbeat-confirmed recording state.
- Marigold is for marks only; red only for live capture.
- iOS builds need macOS (Mac or CI); the owner works on Windows.
