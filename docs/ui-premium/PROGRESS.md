# Premium UI progress

## 2026-11-23 · Phase 0 foundation
- Tokens (`app/lib/app/design/tokens.dart`), theme with Mona Sans type scale (`theme.dart`), `PressableScale` (touch-down feedback, UI-MOTION-001 without overshoot).
- Idle Record screen rendered in goldens (dark, text 1.0 and 2.0) and on an Android emulator.
- Found and fixed in the render: the 76 sp timer wrapped at 200% text size → now scales down to fit.
- Font note: Mona Sans' tabular zero is slashed (`zero.tf`); its ss08 is a barred zero, not a plain one. Kept the slashed zero as an instrument-readout detail. If the owner dislikes it, the fix is a different numeral font for timers.

## 2026-11-23 · Phase 1 Record screen (live)
- New shared pieces in `app/lib/features/record/widgets.dart`: `StatePill` (red dot only while frames flow), `LevelLine` (rise 50 ms / fall 300 ms), `RollingCount` (200 ms), `RibbonGlyph`, `BookmarkZone` (marks on touch-down, haptic, 0.97 press), `MarkRow` (2 s marigold outline on the newest), `RoundControl` (56 dp).
- Patterns: UI-MOTION-001 (touch-down), UI-MOTION-023 (tokens), UI-FEEDBACK-029 (haptic + visual on the mark frame). Outcomes recorded in the library.
- Goldens: live dark x1/x2, landscape. Found in the render: at 200 % text the marks list pushed the controls off screen → the list now takes only the space left and scrolls.
- Found on the emulator: the recording notification landed in the collapsed "Silent" group (Mark hidden; many phones hide silent notifications on the lock screen) → default-importance channel with no sound + compact media layout showing Mark / Pause / Stop.
- Not done yet (Phase 4 polish): falling ribbon animation from the zone into the list, calm mode, light theme on Record.

## 2026-11-24 · Phase 2 Library, Playback, Clip sheet
- New: `RibbonFlag` (numbered, 48 dp hit area, logo ribbon), `Waveform` (CustomPainter over peaks.bin; played/unplayed, mark lines, grey interruption lines, clip range tint, slider semantics), `RecordingRow`, sheets (`showAppSheet`, `askText`, `confirm`, `chooseAction`, `SheetButton`, `IconTap`).
- Theme now follows the system; goldens in dark and light for Library, Playback, Clip sheet, plus Playback at 200 % text.
- Found in the renders and fixed: mark rows overflowed at 200 % text → actions move under the mark; idle Record overflowed in landscape after the Library button → scrolls when needed; date-titled rows repeated the time in the subtitle → length only.
- Emulator (light theme): Library, Playback after a flag jump, Clip sheet, system share sheet with the named clip file — all as designed.
- Not yet (Phase 4): row slide-out animation on delete (UI-FEEDBACK-006), sheet grow-from-trigger (B1), handle release velocity; the waveform's played colour is loud with dense audio — review on real speech.
