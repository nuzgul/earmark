# "Make it expensive" + accessibility audit — 2026-11-24 (Phase 4)

Scope: Record (idle, live, calm, quick labels), Library, Playback, Clip sheet, Settings, Pro, batch share.
Measured by widget tests where a test can measure (`app/test/expensive_test.dart`, `app/test/phase4_test.dart`);
the rest by code reading. Clips on a real phone are still pending (see the end).

| Check | Result | Where / measured | Pattern |
|---|---|---|---|
| A1 touch-down < 100 ms | pass | Bookmark: raw pointer down → pressed scale 0.97 in the first frame, press-in token 90 ms (`expensive_test` A1). Other controls: `PressableScale` `onTapDown`; inside scrolling lists Flutter's 100 ms tap timeout is the floor. | UI-MOTION-001 |
| A2 confirmation on the control used | pass | Mark: zone sinks, newest row outlined 2 s, count rolls. Share clip / Share N clips / Buy Pro: the button itself says "Making clip 2 of 5…" / "Waiting for the store…". Saved: the Saved strip. Delete mark: row leaves + Undo snackbar. | UI-FEEDBACK-007 |
| A3 48 dp targets | pass | `IconTap` 48, `RoundControl` 56, flags and clip handles 48, settings rows 56, chips min 48, speed chip 48. | UI-BUTTON-003 |
| A4 one focus style | n/a (phone) | Touch-only app; hardware-keyboard focus not styled. Low. | UI-WEB-009 |
| A5 haptic on the moments that matter | **fixed** | Mark: one `mediumImpact` on the touch-down frame; quick-label arc: `selectionClick` on open and per label; **added** saved → `lightImpact`, save failed → `heavyImpact`; none on ordinary taps (`expensive_test` counts platform calls). | UI-FEEDBACK-029 |
| B1 surfaces grow from the trigger | failed, Medium | Sheets use the platform bottom sheet (slides from the bottom edge). A grow-from-trigger sheet is a design-system change → for the owner. | UI-MOTION-007 |
| B2 drag follows the finger 1:1 | pass | Clip handles move by the drag delta from where they were grabbed; quick-label arc follows the finger (hover by distance). | UI-MOTION-024 |
| B3 release keeps its speed | n/a by design | Clip handles are precise range edges; a fling would overshoot the moment. | UI-MOTION-025 |
| B4 interruptible | pass | Implicit animations retarget mid-flight; no input locks. | UI-MOTION-017 |
| B5 edges resist | pass | Platform scroll physics (stretch / bounce). | UI-MOTION-026 |
| B6 no overshoot | pass | `easeOut` everywhere, no springs. | UI-MOTION-023 |
| B7 expanding content pushes neighbours | failed, Low | A deleted mark row disappears at once (Undo restores it); no slide-out yet. | UI-FEEDBACK-006 |
| B8 transform / opacity only | **fixed** | Level line animated its width 20×/s for the whole session → now a scale transform. Record button's busy state animated width/height → now scale + opacity. | UI-PERF-008 |
| B9 reduced motion | pass | `Motion.of` returns zero when the system asks; press and calm transitions are instant (`expensive_test` B9). | UI-WEB-002 |
| C1 type per size | pass | Tracking −0.04 on the timer to +0.08 on small labels; follows system text size (goldens at 200 %). | UI-TYPE-008 |
| C2 bars and sheets as layers | pass | Sheets on `surface` over a dimmed page; no translucent bars. | UI-SHADOW-003 |
| C3 depth by dimming | pass | Modal sheets dim the page. | UI-COMP-028 |
| C4 fixed action bar legible | pass | "+ Mark at …" sits below the list, never over content. | UI-COLOR-013 |
| C5 back restores the place | pass | Library keeps its search and scroll under Playback (route stack). | UI-NAV-015 |
| C6 back closes the overlay | pass | System back closes sheets. | UI-WEB-004 |

## Accessibility pass
- **Fixed:** Settings at 200 % text overflowed by 234 px (pre-roll chips in a row) → they wrap (`expensive_test` "Settings sheet fits at 200 % text").
- Screen reader on → calm screen never dims or swallows a touch (`expensive_test`).
- Quick labels without the gesture: Bookmark offers custom actions "Bookmark as Idea / To-do / Quote / Question" (TalkBack and VoiceOver actions menu).
- New controls are labelled: speed ("Playback speed 1.5×. Change"), pre-roll choices (selected, one of a group), batch share rows (checked), Pro buttons (disabled with the reason in text), label announcements ("Mark 3 labelled Idea").
- Contrast: quick-label chips marigold on #1A1405 ≈ 11:1. Calm mode dims secondary controls to 35 % on purpose; the first touch restores them.

## For the owner
- B1: sheets that grow from the control that opened them (custom route; affects every sheet).
- B7: deleted mark rows slide out before the list closes the gap.

## Pending (needs a phone)
Haptic strength on real hardware; calm screen over a 1-hour recording (OLED); quick-label arc with a thumb; screen-reader pass with TalkBack and VoiceOver.
