# Code review 2026-11-24 — findings and status

Owner request: "review the app code … what should be fixed and optimised, I want this app bug free", then a premium-ui expensive-mode pass. Android first; iOS (Swift) is out of scope for now (same design, so engine findings E1–E3 likely apply to `ios/Runner/Engine/` too).

Three independent read-only reviews (engine, data/state, screens). Every finding gets a regression test that fails before the fix where a test can reproduce it; `app/test/review_test.dart` holds the Dart ones (13 reproduced and failing before fixes on 2026-11-24).

Status: `open` → `fixed` (with the test) / `wontfix` (with the reason).

## Engine (Kotlin, `android/app/src/main/kotlin/app/earmark/recorder/engine/`)
| id | sev | finding | status |
|---|---|---|---|
| E1 | high | Low-storage stop: remux needs a second copy, fails with ENOSPC, leaves `audio.m4a.tmp` filling the disk; repeats on every recover | open |
| E2 | high | ANR: `recover()` holds the engine lock during long remuxes; `start()` waits on the main thread; `start()` does I/O on main | open |
| E3 | high | Finalize deletes the part before reading meta.json; missing/torn meta (not fsynced) → recording orphaned; renames unchecked; truncated remux still deletes the part | open |
| E4 | med | fsync on the capture thread can overrun the ~0.5 s AudioRecord buffer (silent audio loss, early marks) | open |
| E5 | med | mic-reopen loop leaks AudioRecords when start() fails; no wake lock while the mic is lost; start() leaks source/codec on later failures | open |
| E6 | med-low | Call-silencing callback appends to the journal on main without runCatching → crash at 0 bytes free | open |
| E7 | low | Capture-thread state changes not atomic with stop/pause (stuck RECORDING+wantPaused) | open |
| E8 | low | Marks fsynced, audio only every 5 s: after power loss marks can point past the audio; not clamped | open |
| E9 | low | RecorderService trusts snapshot order (stale IDLE → stopSelf before startForeground crash) | open |
| E10 | low | Tile/notification marks fsync on the main thread; mark holds the session lock across fsync | open |
| E11 | low | Clip names cut by UTF-16 units (loses ".m4a", >255 bytes with CJK); start past the end exports the last frame | open |
| E12 | low? | API 26–28: silencing not detected (zero samples) | open |

## Data / state (Dart)
| id | sev | finding | status |
|---|---|---|---|
| D1 | high | Concurrent writes to one library.json / settings.json lose edits; shared .tmp name; addMark reads nextN before the write (duplicate numbers) | open |
| D2 | high | Unparsable library.json / settings.json treated as `{}` and then overwritten → added marks, labels, Pro lost | open |
| D3 | med-high | Pro sheet stuck "Waiting for the store…": Play cancel arrives with productID ''; buyNonConsumable false ignored | open |
| D4 | med | Pro: restored PENDING purchase counted as owned; completePurchase result ignored; no silent startup restore/ack; setPro not awaited before ack | open |
| D5 | med | load() is synchronous on the UI isolate (1000 recordings ≈ 1–3 s cold); one bad folder or setting aborts the whole load | open |
| D6 | med-low | dayGroup off by one across DST | open |
| D7 | low | Quick label uses the recording id at release time; label write not followed by upsert | open |
| D8 | low | Stale snapshot can arrive after a Pause reply (brief "Recording" flash) | open |
| D9 | low | EngineClient.stop() does not catch PlatformException; restore timer not cancelled; clip names unbounded; RecorderEvents not unregistered on dispose | open |

## Screens (Dart)
| id | sev | finding | status |
|---|---|---|---|
| U1 | high | Calm screen in the light theme: timer and count stay dark ink on black | open (test fails) |
| U2 | high | Clip sheet: first Preview tap never shows Stop preview / playhead | open (test fails) |
| U3 | med | Recording restored from Recently deleted stays hidden in the Library | open (test fails) |
| U4 | med | Double tap on Stop → false "Couldn't finish saving" + heavy haptic | open (test fails) |
| U5 | med | Sheets overflow at large text / landscape with keyboard; clip nudge row; SheetButton fixed height | open (tests fail) |
| U6 | med | Live Record overflows at 200 % text on a 360×640 phone | open (test fails) |
| U7 | med | Playback: file that won't open fails silently; work after dispose | open (test fails) |
| U8 | med | Waveform drag sends ~60–120 seeks per second | open (test fails) |
| U9 | med | Batch share: setState after the sheet is closed; share sheet opens anyway | open (test fails) |
| U10 | low-med | Second finger on Bookmark ignored; pointer state can stick when disabled mid-touch | open (test fails) |
| U11 | low-med | "+ Mark" double tap → duplicate numbers; position up to 200 ms stale | open (test fails) |
| U12 | low | Level line animates ~40 % of frames, no RepaintBoundary | open |
| U13 | low | Clip handles: <1 s recording throws; handles not clamped to the view; live during export | open (test fails) |
| U14 | low | Preview double-tap / dismissed-sheet races; _share catches PlatformException only | open |
| U15 | low | Pro buy false / two restore timers (see D3, D9) | open |
| U16 | low | Settings write race (see D1) | open |
| U17 | low | Lazy player created in dispose; vanished recording shows a blank screen while playing; unmounted _say; İ highlight RangeError; stale Saved strip | open |
| U18 | low | Semantics: disabled PressableScale and the unavailable Bookmark not marked disabled; overlapping flags | open |
| U19 | low | askText's TextEditingController not disposed | open |
