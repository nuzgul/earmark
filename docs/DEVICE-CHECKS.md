# Device checks (need a physical phone)

Emulators prove the logic; these prove the hardware and the OEM. Record date, phone, Android/iOS
version and result for each line. Install the debug build side by side with any store version
(never over it), and never clear app data on the owner's phone.

Debug APK: `app/build/app/outputs/flutter-apk/app-debug.apk` (build: `flutter build apk --debug` in `app/`).

## Android — Phase 1 (recording engine)

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| A1 | Real-mic timing | Record, watch the timer, tap Bookmark at 00:10; pause 5 s; resume; tap at 00:20; Stop | Marks 00:10 and 00:20 (± 0.1 s) | not run |
| A2 | Screen-locked recording, 10+ min | Start, lock the phone, wait 10 min, unlock | Timer ≈ wall time; file plays to the end | not run |
| A3 | Mark from the lock screen | While locked: notification → Mark (no unlock) | Mark count +1, mark in the right place | not run |
| A4 | Pause/Resume/Stop from the lock screen | Same notification | State follows; Stop saves | not run |
| A5 | Quick Settings tile while locked | Add "Mark moment" tile; tap while recording | Mark added | not run |
| A6 | Incoming call | Answer a real call mid-recording, hang up | "Paused: call", timer holds; resumes after the call | not run |
| A7 | Bluetooth mic loss | Record on a BT headset, switch it off | Recording continues on the phone mic (no gap > 1 s) | not run |
| A8 | Low storage | Fill storage to < 150 MB, record | Refuses below 100 MB at start; stops and saves below 50 MB | not run |
| A9 | OEM battery killer | Samsung / Xiaomi, 30 min locked | Still recording; if killed, "Recovered" on next open | not run |
| A10 | 1-hour recording | Record 60 min, Stop | Saves in < 3 s; duration 60:00 | not run |
| A11 | TalkBack | Full Record flow with TalkBack | Every control named; marks announced "Mark N at …" | not run |
| A12 | Notification permission refused | Deny notifications at first Record | Recording works; no lock-screen controls (explained in Phase 2 settings) | not run |

Verified on the emulator (Android 15, 2026-11-23): locked-screen recording (20 s), notification
Mark/Pause/Resume from the shade, Quick Settings tile marks, simulated answered call
("Paused: call", auto-resume, call marker in the journal), `kill -9` mid-recording → "Recovered"
with all marks, install-over-a-running-recording → recovered.

## Android — Phase 2 (library, playback, clips)

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| B1 | Real recording replay | Record 2 min speech with 3 marks; Library → open → tap each flag | Plays from 3 s before each mark; voice matches the moment | not run |
| B2 | Share clip to a real app | Share clip → WhatsApp / Gmail / Drive | Receiver plays a 20 s .m4a named "… — Mark N (mm-ss to mm-ss).m4a" | not run |
| B3 | Clip preview | Clip sheet → Preview | Plays exactly the selected range and stops | not run |
| B4 | Handles by finger | Drag both clip handles | Follow the finger; readout updates; min 1 s | not run |
| B5 | Long file | Open a 1-hour recording | Opens < 1 s; waveform and flags drawn; seeking smooth | not run |
| B6 | Headphones / Bluetooth playback | Play through BT headphones; disconnect | Playback pauses on disconnect (no speaker blast) | not run |
| B7 | Light and dark | Switch system theme | Both readable; marigold only on marks | not run |

## iOS — Phase 3 (needs an iPhone and an Apple Developer account to install)

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| C1 | Owner sequence, real mic | Record 10 s → Mark → Pause 5 s → Resume 10 s → Mark → Stop | Marks at 00:10 and 00:20 (± 0.1 s); paused time not in the file | not run |
| C2 | Locked screen, 10+ min | Start, lock, wait 10 min, unlock | Timer and file both 10+ min; no gap | not run |
| C3 | Live Activity Mark | Lock screen → Mark (and in the Dynamic Island) | Mark lands at that moment; count in the activity goes up | not run |
| C4 | Live Activity Pause / Stop | Pause, Resume, Stop from the lock screen | App shows the same state; Stop saves the recording | not run |
| C5 | Control Center control (iOS 18) | Add "Record or mark"; tap with the app closed, then again | First tap starts recording with a Live Activity; second tap marks | not run |
| C6 | Action Button (15 Pro and later) | Assign the control; press while recording | A mark at that moment | not run |
| C7 | Incoming call | Call the phone while recording; hang up | "Paused: call" marker; recording continues after the call | not run |
| C8 | Siri / alarm interruption | Trigger Siri or a timer alarm | Same as C7 | not run |
| C9 | Bluetooth mic lost | Record with AirPods, take them out | Continues on the iPhone mic within ~2 s | not run |
| C10 | Kill mid-recording | Record 1 min, swipe the app away | Next launch: "Recovered" recording with its marks | not run |
| C11 | Mic permission refused | Deny at first Record | Card with Open Settings; library still works | not run |
| C12 | VoiceOver | Record, mark, open, share with VoiceOver on | Every control has a label and state | not run |
| C13 | 1-hour recording | Record 60 min, Stop | Saves in a few seconds; plays; clips export | not run |
