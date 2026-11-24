# "Make it expensive" — round 2 (2026-11-24, after the bug-free pass)

Round 1 (`AUDIT-expensive-2026-11-24.md`) left two checks failed: **B1** (surfaces grow from what was touched)
and **B7** (removed content: the row leaves, then its neighbours close the gap). This round fixes both, re-checks
all 20 on the code as it now ships, and records before / after on the emulator.

**What to expect from the pictures:** both fixes are motion. The still screenshots are meant to look the same
before and after; the evidence is the clips and the frame-by-frame numbers below.

## How it was recorded
- Device: Android emulator `Shared_API35` (1080×2400), booted without saving a snapshot; same script, same data,
  light and dark: `app/tool/capture_android.sh emulator-5554 <dir> light|dark` drives
  `app/integration_test/capture_test.dart` (builds a library with the debug-only test tone: 3 recordings,
  "Pitch rehearsal" with 3 marks, one renamed "Budget question").
- **Handshake** (new this round): the test names each scene and waits until the host has taken the screenshot
  (or started the screen recording) and written the name back. The first after-run had no handshake and two
  light stills were taken late (the next sheet already opening): 40–71 % "changed" that was only timing.
- Before = commit `29103a7` (checked out in a separate worktree, same capture tooling); after = this commit.
  Each run alone on the emulator (a first before-run overlapped a stray second run and was thrown away).
- Pixel diff: share of pixels whose largest channel difference is above 24/255, status bar excluded.

## Before | after
| Screen | Light, % of pixels changed | Dark | What differs |
|---|---|---|---|
| Record, idle | 0.06 | 0.06 | free-space text ("116 h" / "114 h") |
| Record, live (2 marks) | 0.00 | 0.40 | timer digits |
| Library | 0.14 | 0.16 | recording times in the titles |
| Playback | 0.63 | 0.27 | recording time in the subtitle, waveform of the test tone |
| Share clip sheet | 0.79 | 0.33 | clip length 12.1 / 12.2 s and its waveform (where the playhead stood) |
| Settings | 0.04 | 0.06 | timer digits behind the sheet |
| Pro sheet | 0.01 | 0.01 | timer digits behind the sheet |
| **Row menu open (B1)** | **81.34** | **15.98** | **before: a sheet across the bottom and the whole page dimmed; after: a menu at Mark 3's ⋯, page not dimmed** |

Every screen except the open menu is unchanged, as intended (motion-only fixes).

Pairs side by side: `expensive/pairs-light.png`, `expensive/pairs-dark.png`. Single files:
`expensive/before/<theme>-<screen>.png`, `expensive/after/<theme>-<screen>.png`, clips `…-clip_*.mp4`.

## The 20 checks

| Check | Result | Where / measured | Pattern |
|---|---|---|---|
| A1 touch-down < 100 ms | pass | Bookmark: pressed scale 0.97 on the first frame after touch-down, press-in token 90 ms (`expensive_test` A1). | UI-MOTION-001 |
| A2 confirmation on the control used | pass | Unchanged from round 1; Delete mark: the row itself leaves, then "Mark 3 deleted · Undo". | UI-FEEDBACK-007 |
| A3 48 dp targets | pass | Menu items 52 dp high, min width 200 dp. | UI-BUTTON-003 |
| A4 one focus style | n/a (phone) | Touch-only app. | UI-WEB-009 |
| A5 haptic on the moments that matter | pass | One `mediumImpact` on the mark frame, `lightImpact` on saved, none on ordinary taps or menus (`expensive_test`). | UI-FEEDBACK-029 |
| B1 surfaces grow from the trigger | **fixed** (menus) | Row menus (Playback mark ⋯, Library row ⋯, Recently deleted ⋯) were bottom sheets from the screen edge; now a menu anchored at the finger, growing out of the ⋯ and fading back into it (`app/lib/app/design/sheets.dart` `chooseAction`). Stills `before|after/<theme>-mark_menu.png`: before, a sheet across the bottom of the screen; after, the menu at Mark 3's ⋯. Test (`expensive_test` B1): menu item centre within 160 px of the ⋯ that was tapped, no `BottomSheet`, closes on an outside tap. Full sheets (clip editor, settings, Pro) stay platform bottom sheets: see "for the owner". | UI-MOTION-007 |
| B2 drag follows the finger 1:1 | pass | Unchanged. | UI-MOTION-024 |
| B3 release keeps its speed | n/a by design | Clip handles are exact range edges. | UI-MOTION-025 |
| B4 interruptible | pass | The leaving row ignores taps (no double delete); everything else retargets mid-flight. | UI-MOTION-017 |
| B5 edges resist | pass | Platform scroll physics. | UI-MOTION-026 |
| B6 no overshoot | pass | `easeOut` throughout; the menu uses the platform's fade + size curve. | UI-MOTION-023 |
| B7 removed content: leave, then close the gap | **fixed** | Shared `LeaveOut` (`app/lib/app/design/leave_out.dart`), used by Playback (delete mark) and Library (Delete from the ⋯ menu; a swipe already slid out and closed through the platform `Dismissible`). 320 ms (2 × the exit token, `easeOut`): the row slides 25 % left and fades, then its height closes. Measured every 20 ms (`expensive_test` B7): Mark 2 opacity 0.79 / 0.60 / 0.42 / 0.24 / 0.08 / 0 at 20–120 ms while Mark 3 holds still; then Mark 3 rises 5.2 → 14.7 → 23.5 → 31.9 → 39.3 → 46.2 → 52.0 → 56.9 → 60.7 → 63.1 → 64.0 px (120–320 ms), at most 9.5 px per frame, never down. Library: the next row only moves up, < 16 px per frame, ≥ 40 px in total, and does not move again when the collapsed row is finally removed. Before: the row vanished in one frame and everything below jumped 64 px. | UI-FEEDBACK-006, UI-MOTION-015 |
| B8 transform / opacity only | pass, one bounded exception | The leaving row animates opacity + translation; its height collapse (≈200 ms, one row, once per delete) is a layout animation, which is the only way neighbours can move into the gap. | UI-PERF-008 |
| B9 reduced motion | pass | Menu opens with no animation, the row goes at once (`expensive_test` B9). | UI-WEB-002 |
| C1 type per size | pass | Unchanged. | UI-TYPE-008 |
| C2 bars and sheets as layers | pass | The menu is `raised` with a hairline border, no shadow (matches the app's flat surfaces). | UI-SHADOW-003 |
| C3 depth by dimming | pass | Blocking sheets dim; the menu (non-blocking, light) does not. | UI-COMP-028 |
| C4 fixed action bar legible | pass | Unchanged. | UI-COLOR-013 |
| C5 back restores the place | pass | Unchanged. | UI-NAV-015 |
| C6 back closes the overlay | pass | System back closes the menu (popup route) and sheets. | UI-WEB-004 |

## Accessibility of the new parts
- Screen reader on: a TalkBack / VoiceOver double tap is not a touch, so the last finger position would be stale.
  `chooseAction` then falls back to the bottom sheet (`MediaQuery.accessibleNavigation`).
- Menu items keep the labels "Rename mark" / "Delete mark"; Delete is in the live-capture red (danger), as before.
- Reduced motion: both changes are instant.

## Measurement limits (said plainly)
- The emulator's screen recorder delivered only 3–5 frames a second under load (software rendering, busy host):
  `after/light-clip_delete_mark.mp4` has 9 frames in 3 s, and the before clip missed the open sheet entirely. So
  the clips show before and after states, not the motion; the evidence for B1 is the `mark_menu` stills and the
  test, for B7 the 20 ms widget-test frames above.
- Frame-time budget (< 1 % janky frames) needs a real GPU: still pending on a phone.

## For the owner
- B1 for the big sheets (clip editor, Settings, Pro): they slide up from the bottom edge, as both platforms do.
  Making them grow out of the button would be a custom route for every sheet and would cost drag-to-dismiss
  behaviour; recommended to keep.

## Pending (needs a phone)
Frame timing on a real GPU; the menu and row exit at 120 Hz; TalkBack and VoiceOver pass on the new menu
fallback; haptic strength.
