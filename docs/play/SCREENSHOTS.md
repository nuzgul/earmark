# Google Play graphics — Earmark (2026-11-25)

Same design system as the owner's PDF NOVA listing (`E:\CLAUDE PROJECTS\app-pdf-nova\docs\play\SCREENSHOTS.md`), in
Earmark's palette and type.

## Make them (Git Bash, from `app/`, emulator `Shared_API35` running)
1. `TEST=integration_test/store_tour_test.dart tool/capture_android.sh emulator-5554 build/store/raw light`
2. the same with `dark`
3. `python tool/play/make_graphics.py build/store/raw ../dist/play-store-assets`

Output (git-ignored `dist/`): `screenshots/en/NN_<key>.png` (1080×1920, upload in file order),
`feature-graphic/feature_graphic_en.png` (1024×500), `previews/contact_sheet_en.png` (review only), `source/en/*.html`
(the page each PNG was rendered from), `logo/icon_play_512.png`. Play specs: 24-bit PNG without alpha, long side ≤ 2×
short side, 9:16 ≥ 1080×1920, at least 4 and up to 8 phone screenshots.

## Inputs
`build/store/raw/<theme>-<scene>.png`: real app captures (1080×2400) from `integration_test/store_tour_test.dart`, which
builds a small library with the debug-only test tone ("Weekly team sync" with marks Budget question / Launch date /
Action items, "Interview with Sam", "Idea: onboarding flow"). The tone's flat level would draw a flat waveform, so the
tour writes a speech-like envelope into each recording's `peaks.bin` (display data only; the audio is untouched). Pro is
switched on for the capture (quick labels) and off again at the end. The system status bar and gesture bar are replaced
by a neutral bar; everything inside the phone is the unmodified app screen. Callouts are enlarged crops of the same
capture (`BOXES` in the generator; re-measure them when a capture is retaken).

## Art direction
- Logo: a marigold bookmark crossed by one voice wave (`docs/brand/make_logo.py`, v3 of 2026-11-25; chosen to differ from the owner's other apps: no folds, no moon, no bar chart).
- Palette from the app: carbon `#14130F`, cream `#F3EEE2`/`#F7F3EA`, marigold `#FFC23D` → `#F2A81C`. Backgrounds
  alternate cream → night → cream → marigold → cream → night → marigold. One sound-wave ribbon runs through all slides.
- Mona Sans (the app's font) headlines, 3–7 words, one highlighted phrase (marigold pill on cream, marigold text on
  night, carbon pill on marigold); one supporting line.
- Phones: CSS device (bezel, punch-hole, side keys) at varied 3D angles, two-device hero mixing dark and light app
  themes; callouts lift the detail that proves the headline; at most two icon badges per slide.

## Story (order on the listing)
1 hero, mark the moments · 2 one tap to mark (live, dark) · 3 jump to every mark (Playback) · 4 share a clip ·
5 search · 6 quick labels (Pro) · 7 no account, no internet. Claims match `STORE_LISTING.md`.
