# Owner requests

- 2026-11-23: Build a voice recorder for Android **and iOS** around "mark a moment while recording, find it, share just that part" (original Android/Kotlin prompt pasted). Research competitors, add what beats them, give a full detailed expert plan, use /premium-ui (and the expensive-mode reference), modern elegant creative design and a creative logo. → docs/PLAN.md, docs/ui-premium/PLAN.md, docs/design-board.html, docs/brand/.
- 2026-11-23: "Yes, use defaults" → decisions D1–D6 set to the recommendations; Phase 0 (project setup) built.
- 2026-11-23: "Yes, start Phase 1" → Android recording engine, foreground service + notification/tile marks, recovery, Record screen, owner's timing sequence as an integration test.
- 2026-11-24: "Yes, start Phase 2" → Library (search, groups, rename, Recently deleted), Playback (waveform, flags, pre-roll, marks editing), lossless Share clip, clip-content integration test.
- 2026-11-24: "Yes, run it now" → final emulator re-run of both integration tests after the Phase 2 fixes; all passed.
- 2026-11-24: "Yes, start Phase 3" + "Private GitHub repo" → Swift engine, Live Activity, Control Center control, Xcode target, macOS CI job; first compile runs on GitHub after the owner logs in to gh.
- 2026-11-24: "Logged in, push it" + "use chrome, u have full permission" → private repo nuzgul/earmark created and pushed; iOS app and widget compile on CI; all three integration tests pass on the iPhone simulator.
- 2026-11-24: "Yes, start Phase 4" → Pro purchase (in_app_purchase), Settings, calm screen, quick labels, batch clip share, playback speed, expensive/a11y audit. "try s24 is connected" → release build tested on the owner's Galaxy S24 FE.
- 2026-11-24: "Wait for monthly reset" → CI stays paused until the GitHub Actions minutes renew; then re-run run 45377906690.
- 2026-11-24: "forget the IOS for now and do like all other apps" + "remove earmark from private to public" → repo made public (history checked first), iOS CI job manual-only, pushes run Android CI.
- 2026-11-24: "/be-ambitious review the app code … bug free, then /premium-ui and expensive-mode" → 3 reviews, 38/40 findings fixed with tests, CI emulator job, S24 fault checks (partly). "stop the test and close the emulator" → stopped; progress saved here.
