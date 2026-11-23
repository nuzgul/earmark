# Premium UI progress

## 2026-11-23 · Phase 0 foundation
- Tokens (`app/lib/app/design/tokens.dart`), theme with Mona Sans type scale (`theme.dart`), `PressableScale` (touch-down feedback, UI-MOTION-001 without overshoot).
- Idle Record screen rendered in goldens (dark, text 1.0 and 2.0) and on an Android emulator.
- Found and fixed in the render: the 76 sp timer wrapped at 200% text size → now scales down to fit.
- Font note: Mona Sans' tabular zero is slashed (`zero.tf`); its ss08 is a barred zero, not a plain one. Kept the slashed zero as an instrument-readout detail. If the owner dislikes it, the fix is a different numeral font for timers.
