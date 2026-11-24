# Code review 2026-11-24 — findings and status

Owner request: "review the app code … what should be fixed and optimised, I want this app bug free", then a premium-ui expensive-mode pass. Android first; iOS (Swift) is out of scope for now (same design, so engine findings E1–E3 likely apply to `ios/Runner/Engine/` too).

Three independent read-only reviews (engine, data/state, screens). Every finding gets a regression test that fails before the fix where a test can reproduce it; `app/test/review_test.dart` holds the Dart ones (13 reproduced and failing before fixes on 2026-11-24).

Status: `open` → `fixed` (with the test) / `deferred` (with the reason).

Result 2026-11-24: engine E1–E11 + E13 fixed by a separate engineer agent (JVM `FinalizeLogicTest` 10 + `EngineLogicTest` 5); Dart D1–D7, D9 and U1–U19 fixed with `test/review_test.dart` (19 tests, all failing before the fixes) and `test/phase4_test.dart` (Pro). `flutter analyze` clean, `flutter test` 65/65.
Extra from Android Lint: E13 `FOREGROUND_SERVICE_TYPE_MICROPHONE` (API 30) behind a Q guard → R; fixed.
Device checks still to run: S24 integration + kill -9 recovery + Record during recovery (E2) + wake lock (E5) + rapid stop/start (E9) + frame timing; emulator disk-full (E1) and damaged part / lost meta (E3).

## Engine (Kotlin, `android/app/src/main/kotlin/app/earmark/recorder/engine/`)
| id | sev | finding | status |
|---|---|---|---|
| E1 | high | Low-storage stop: remux needs a second copy, fails with ENOSPC, leaves `audio.m4a.tmp` filling the disk; repeats on every recover | fixed (JVM test where pure; device check pending) |
| E2 | high | ANR: `recover()` holds the engine lock during long remuxes; `start()` waits on the main thread; `start()` does I/O on main | fixed (JVM test where pure; device check pending) |
| E3 | high | Finalize deletes the part before reading meta.json; missing/torn meta (not fsynced) → recording orphaned; renames unchecked; truncated remux still deletes the part | fixed (JVM test where pure; device check pending) |
| E4 | med | fsync on the capture thread can overrun the ~0.5 s AudioRecord buffer (silent audio loss, early marks) | fixed (JVM test where pure; device check pending) |
| E5 | med | mic-reopen loop leaks AudioRecords when start() fails; no wake lock while the mic is lost; start() leaks source/codec on later failures | fixed (JVM test where pure; device check pending) |
| E6 | med-low | Call-silencing callback appends to the journal on main without runCatching → crash at 0 bytes free | fixed (JVM test where pure; device check pending) |
| E7 | low | Capture-thread state changes not atomic with stop/pause (stuck RECORDING+wantPaused) | fixed (JVM test where pure; device check pending) |
| E8 | low | Marks fsynced, audio only every 5 s: after power loss marks can point past the audio; not clamped | fixed (JVM test where pure; device check pending) |
| E9 | low | RecorderService trusts snapshot order (stale IDLE → stopSelf before startForeground crash) | fixed (JVM test where pure; device check pending) |
| E10 | low | Tile/notification marks fsync on the main thread; mark holds the session lock across fsync | fixed (JVM test where pure; device check pending) |
| E11 | low | Clip names cut by UTF-16 units (loses ".m4a", >255 bytes with CJK); start past the end exports the last frame | fixed (JVM test where pure; device check pending) |
| E12 | low? | API 26–28: silencing not detected (zero samples) | deferred: API 26–28 only, needs a device to tune |

## Data / state (Dart)
| id | sev | finding | status |
|---|---|---|---|
| D1 | high | Concurrent writes to one library.json / settings.json lose edits; shared .tmp name; addMark reads nextN before the write (duplicate numbers) | fixed (test) |
| D2 | high | Unparsable library.json / settings.json treated as `{}` and then overwritten → added marks, labels, Pro lost | fixed (test) |
| D3 | med-high | Pro sheet stuck "Waiting for the store…": Play cancel arrives with productID ''; buyNonConsumable false ignored | fixed (test) |
| D4 | med | Pro: restored PENDING purchase counted as owned; completePurchase result ignored; no silent startup restore/ack; setPro not awaited before ack | fixed (test) |
| D5 | med | load() is synchronous on the UI isolate (1000 recordings ≈ 1–3 s cold); one bad folder or setting aborts the whole load | fixed (test) |
| D6 | med-low | dayGroup off by one across DST | fixed (test) |
| D7 | low | Quick label uses the recording id at release time; label write not followed by upsert | fixed (test) |
| D8 | low | Stale snapshot can arrive after a Pause reply (brief "Recording" flash) | deferred: needs a sequence number in the Pigeon snapshot (engine + Dart) |
| D9 | low | EngineClient.stop() does not catch PlatformException; restore timer not cancelled; clip names unbounded; RecorderEvents not unregistered on dispose | fixed (test) |

## Screens (Dart)
| id | sev | finding | status |
|---|---|---|---|
| U1 | high | Calm screen in the light theme: timer and count stay dark ink on black | fixed (test) |
| U2 | high | Clip sheet: first Preview tap never shows Stop preview / playhead | fixed (test) |
| U3 | med | Recording restored from Recently deleted stays hidden in the Library | fixed (test) |
| U4 | med | Double tap on Stop → false "Couldn't finish saving" + heavy haptic | fixed (test) |
| U5 | med | Sheets overflow at large text / landscape with keyboard; clip nudge row; SheetButton fixed height | fixed (test) |
| U6 | med | Live Record overflows at 200 % text on a 360×640 phone | fixed (test) |
| U7 | med | Playback: file that won't open fails silently; work after dispose | fixed (test) |
| U8 | med | Waveform drag sends ~60–120 seeks per second | fixed (test) |
| U9 | med | Batch share: setState after the sheet is closed; share sheet opens anyway | fixed (test) |
| U10 | low-med | Second finger on Bookmark ignored; pointer state can stick when disabled mid-touch | fixed (test) |
| U11 | low-med | "+ Mark" double tap → duplicate numbers; position up to 200 ms stale | fixed (test) |
| U12 | low | Level line animates ~40 % of frames, no RepaintBoundary | fixed (test) |
| U13 | low | Clip handles: <1 s recording throws; handles not clamped to the view; live during export | fixed (test) |
| U14 | low | Preview double-tap / dismissed-sheet races; _share catches PlatformException only | fixed (test) |
| U15 | low | Pro buy false / two restore timers (see D3, D9) | fixed (test) |
| U16 | low | Settings write race (see D1) | fixed (test) |
| U17 | low | Lazy player created in dispose; vanished recording shows a blank screen while playing; unmounted _say; İ highlight RangeError; stale Saved strip | fixed (test) |
| U18 | low | Semantics: disabled PressableScale and the unavailable Bookmark not marked disabled; overlapping flags | fixed (test) |
| U19 | low | askText's TextEditingController not disposed | fixed (test) |

## Device and CI checks (2026-11-24, stopped by the owner before the end)
- CI run 45427418539 (a0d18b3): android job green; the new android-integration job ran the tests on a 320×640 emulator and found two small-screen layout bugs (not engine bugs): Playback transport overflowed 16 px at 320 dp (clip test failed), and the live Record column scrolled Pause/Stop under the Bookmark zone (owner sequence could not tap Stop). Fixed after a0d18b3: transport buttons shrink to ≥ 48 dp; only the middle of the live column scrolls. Regression tests: "small 320 dp phone …" in `test/review_test.dart`. The clip test itself passed on that emulator (clip 20.010 s, pitch 400 Hz).
- S24 (`tool/fault_android.sh R5CX92TT0VB`, test tone): five quick Record/Stop cycles → no crash-log entries; wake lock held while recording; `kill -9` at ~31.7 s → the part file held ~33 s of audio (406 KB), so nothing was lost at the kill. Not yet measured: recovery after relaunch (the script relaunched the test APK, whose entry point is the test, so the app's recovery never ran) and frame timing (`dumpsys gfxinfo` does not see Flutter's surface).
- Next (when the owner says proceed): in `tool/fault_android.sh`, build `flutter build apk --debug` (real entry point) first and `adb install -r` it after the kill, then relaunch and read meta.json (target < 500 ms lost, mark kept); frame timing now uses `watchPerformance` in `integration_test/fault_test.dart` (debug numbers = upper bound). Emulator only: `tool/disk_android.sh emulator-5554` (low storage, E1) — written, not run yet. Then E3 damaged part / lost meta, then CI re-run.

## Device checks finished on the emulator (2026-11-24, owner: "use emulator")
Outside judges: fault scripts on the `Shared_API35` emulator, CI's emulator job, StrictMode, property tests.

| Check | Result |
|---|---|
| kill -9 mid-recording → reopen the real app (`tool/fault_android.sh`) | **pass**: recovered automatically, 24 853 ms vs ~24 490 ms expected (nothing lost; +363 ms is encoder priming), mark kept, part replaced by audio.m4a, no crash, no ANR |
| Damaged part + lost meta.json (`DAMAGE=1 tool/fault_android.sh`) | **pass**: meta rebuilt (status recovered), the 8.1 s before the damage saved as audio.m4a, the unreadable rest kept as `audio.aac.unread` (never deleted), mark kept, no crash |
| Disk full, ~40 MB left (`tool/disk_android.sh`, emulator only) | **pass**: stopped by itself with stopReason `low_storage`, clean 15 s audio.m4a, no tmp copy, no part left |
| Five quick Record/Stop cycles; wake lock | **pass**: no crash-log entries; `Earmark:recording` wake lock held while recording |
| StrictMode (debug builds, integration tests) | **fixed**: snapshots read free space (StatFs) and ran mkdirs on the main thread 4×/s (100+ violations per run) → free space cached and refreshed off the main thread, folder created once → 0 violations from Earmark code; 1 remaining is Flutter's own engine start-up |
| Owner sequence timing | CI emulator +5 / −11 ms; local emulator +48 / +32 and +90 / +10 ms (test limit ±100 ms passes; the ±50 ms stretch goal holds on CI, not on every run of the busy local emulator — the spread is tap delivery and timer jitter on the host, the engine stamps a mark on receipt) |
| Property tests | Dart `test/property_test.dart` (20 000 clip windows; 400 randomly damaged folders; 150 random edits with double adds) and Kotlin `PropertyTest` (5 000 random byte streams; 2 000 cut streams; 1 000 mid-file damages; 500 journals with junk; 5 000 random clip names) — all pass |
| Android Lint | no app defects; E13 fixed |
| Frame timing (`tool/frames_android.sh`, profile build, emulator) | UI build cost **pass**: average 0.6–1.7 ms per frame on Record while recording with repeated Bookmark taps (real engine, emulator microphone). Raster 25–164 ms per frame is the emulator's software renderer on a fully loaded host, not the app: the "< 1 % janky frames" target **needs a real GPU** (phone) |
| S24 (before "use emulator") | five cycles no crash; wake lock held; kill -9 lost no audio (part held ~33 s) |
