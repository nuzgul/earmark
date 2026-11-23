# Earmark — design direction (premium-ui)

Status: direction chosen 2026-11-23, nothing implemented yet. Platform: Flutter (Android + iOS). Visual reference: [../design-board.html](../design-board.html).

## Product and feel
An instrument you use without looking, then a precise finder. Calm, warm, confident; low density on Record, medium on Library/Playback. Motion level: **subtle** (utility).

## Direction
- **Colour roles.** Warm carbon neutrals tinted toward marigold. **Marigold is reserved for marks** (Bookmark zone, ribbon flags, mark badges, selected clip range). **Red only for live capture** (REC dot, Stop icon). Success green only for "Saved"/"Recovered".
- **Elevation.** Tonal steps only (bg → surface → raised); no shadows except the bottom sheet, whose shadow is tinted carbon. No glass, no gradients.
- **Radius logic.** 28 large containers (Bookmark zone, sheets), 18 rows/cards, 10 small controls, full pill for chips and buttons; nested radius = outer − padding.
- **Spacing.** 4 / 8 / 12 / 16 / 20 / 28 / 40. Screen padding 20.
- **Type.** One variable family for everything, bundled: **Mona Sans** (OFL, width + weight axes; verify tabular figures at setup; fallback Roboto Flex / SF Pro). Scale 13 / 16 / 20 / 25 / 32, display timer 76 (Record) and 56 (landscape). Weights 450 and 600–650. Timer and timestamps: tabular figures, tracking −4% on display, −2% on titles. Sentence case.
- **Navigation.** Record is home; Library top-left; Playback pushed; clip/rename/Pro/settings are bottom sheets. Native back (predictive back on Android, swipe-back on iOS).
- **Responsive.** Portrait-first; landscape puts the Bookmark zone on the right half; tablets show Library + Playback side by side.

## Tokens
| Role | Dark | Light | Contrast (on bg) |
|---|---|---|---|
| bg | #14130F | #F7F3EA | — |
| surface | #1E1C17 | #EFE9DC | — |
| raised | #29261F | #FBF8F1 | — |
| text | #F3EEE2 | #1B1812 | 16.1 / 16.0 |
| text2 | #ADA593 | #5C5547 | 7.6 / 6.7 |
| border (control boundary) | #77705E | #8C8472 | 3.8 / 3.4 |
| accent fill (marks) | #FFC23D | #FFC23D + 1.5 px ring #7A5500 | 11.5 / ring 6.1 |
| on-accent | #1A1405 | #1A1405 | 11.4 on accent |
| accent as text/icon | #FFC23D | #7A5500 | 11.5 / 6.1 |
| rec | #FF6B5E | #B02E22 | 6.7 / 5.3 |
| success | #63D69C | #1B6B43 | 10.3 / 5.4 |

All measured (WCAG formula) against bg and checked on surface/raised; the lowest pair is dark border on raised at 3.06.

Motion tokens (UI-MOTION-023): press-in 90 ms ease-out, entrance 250 ms ease-out, exit 160 ms, ribbon drop 250 ms, count roll 200 ms, sheet spring damping 1.0 (overshoot only after a flick), stagger 50 ms (max 8 items).

## Signature moments
1. **Mark.** On touch-down (not release): the Bookmark zone sinks to 0.97 and darkens 8%, `HapticFeedback.mediumImpact()` on the same frame, and the native `mark()` call goes out at once. A small ribbon falls from the touch point into the marks list (250 ms), the newest row gets a marigold outline for 2 s, and the count rolls. The confirmation stays visible even if the haptic is off. Screen reader: "Mark 3 at 4 minutes 32 seconds" (polite announcement).
2. **Level line.** One thin line whose filled width follows the smoothed level (attack 50 ms, release 300 ms, 20 fps). No bouncing bars: calm over a long session.
3. **Calm mode.** After 20 s without touches: everything except the timer, mark count and Bookmark zone fades to 35%, background to true black on OLED. A touch restores it, and that touch still marks if it lands on the Bookmark zone.
4. **Ribbon flags** on the playback waveform, numbered, each with a 48 dp hit area.

## Patterns used (library ids)
- UI-MOTION-001: press sink on touch-down; spring back without overshoot (house rule: damping ≥ 0.9)
- UI-MOTION-023: duration tokens by role
- UI-FEEDBACK-029: haptic + visual on one frame, only for mark / saved / recovered / error
- UI-FEEDBACK-022: undo for mark delete; confirmation + 30-day Recently deleted for recordings
- UI-FEEDBACK-006: deleted mark row leaves, then the gap closes
- UI-BUTTON-003: hit areas larger than drawings (flags, clip handles, chips)
- UI-NAV-014: search placeholder names what is searched, recents, zero-result recovery
- UI-TYPE-008 + UI-COLOR-005: type scale; tinted off-white instead of #FFFFFF

## Shared components to build once (lib/app/design/)
`AppTokens` (ThemeExtension), `PressableScale`, `BookmarkZone`, `LevelLine`, `RollingCount`, `RibbonFlag`, `WaveformView` (CustomPainter over peaks), `RangeSelector` (clip handles + nudges), `MarkRow`, `UndoSnackbar`, `StatePill`.

## "Make it expensive" checks to run in Phase 4
A1 touch-down < 100 ms on every control · A2 confirmation on the control used · A3 48 dp targets · A5 haptic on the frame · B1 sheets grow from their trigger and leave the same way · B2/B3 handles follow the finger 1:1 and keep release speed · B6 no overshoot · B8 transform/opacity only · B9 reduced motion · C1 type styles · C5 back restores scroll/search. Record results in `docs/ui-premium/AUDIT-expensive-<date>.md`.

## Logo
`docs/brand/logo.svg` (app icon) and `logo-mono.svg` (Android adaptive monochrome layer, notification small icon, iOS tinted icon). Export with `flutter_launcher_icons` at setup (ask before adding it; it is a dev-only dependency).
