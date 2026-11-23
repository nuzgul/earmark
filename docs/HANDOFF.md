# Handoff — Earmark (voice recorder with bookmarks)

## State (2026-11-23)
Planning finished; no app code yet.
- `docs/PLAN.md`: product, competitors, tech stack (Flutter + native Kotlin/Swift audio engines over Pigeon), architecture, screens, verification, roadmap.
- `docs/ui-premium/PLAN.md`: design direction, tokens with measured contrast, signature moments, pattern ids.
- `docs/design-board.html`: logo, palette and five screen mockups (open in a browser).
- `docs/brand/logo.svg`, `logo-mono.svg`.

## When the owner says "proceed"
1. Confirm decisions D1–D6 in `docs/PLAN.md` §13 (name, iOS build route, Pro price, transcription, backups, min iOS). Use the recommendations if the owner says "use defaults".
2. Start Phase 0 (`docs/PLAN.md` §12): check Flutter/Android SDK are installed (`flutter doctor`), create `app/`, CI, tokens, icon, Pigeon skeleton.
3. Then Phase 1 (Android engine + Record), following the execution brief in `docs/PLAN.md` §14.
