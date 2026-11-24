// Contract between the Flutter UI and the native recording engine.
// Regenerate after editing:  dart run pigeon --input pigeons/engine_api.dart
// iOS output (swiftOut) is added in Phase 3, when the Swift engine is built.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/engine/engine_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/app/earmark/recorder/engine/EngineApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.earmark.recorder.engine'),
  ),
)
/// The engine's real state. The UI never shows "Recording" unless the engine says so.
/// `recording` is reported only once microphone frames are actually arriving.
enum SessionState { idle, starting, recording, paused, interrupted, finalizing }

/// Sent on every heartbeat (about every 250 ms) and after every command.
class EngineSnapshot {
  EngineSnapshot({
    required this.state,
    required this.positionMs,
    required this.level,
    required this.markCount,
    required this.freeBytes,
  });

  SessionState state;

  /// Folder id of the recording in progress, null when idle.
  String? recordingId;

  /// Audio actually captured, paused time excluded (frame-counted).
  int positionMs;

  /// Peak input level since the last snapshot, 0.0 to 1.0.
  double level;

  /// User marks only (system markers such as "call" are not counted).
  int markCount;

  /// Why capture is interrupted: "call", "mic_lost". Null otherwise.
  String? interruption;

  /// Free space where recordings are stored.
  int freeBytes;
}

class MarkResult {
  MarkResult({required this.id, required this.positionMs, required this.index});

  String id;

  /// Frame-counted position of the mark in the saved audio.
  int positionMs;

  /// 1-based number used for the automatic name "Mark N".
  int index;
}

/// A finished recording on disk (after Stop, or recovered after a crash).
class SavedRecording {
  SavedRecording({
    required this.id,
    required this.folder,
    required this.createdAtMs,
    required this.durationMs,
    required this.marks,
    required this.recovered,
  });

  String id;

  /// Absolute folder holding audio.m4a, marks.jsonl, peaks.bin, meta.json.
  String folder;

  int createdAtMs;
  int durationMs;
  List<MarkResult> marks;

  /// True when it was rebuilt after the app was killed mid-recording.
  bool recovered;

  /// Why the engine stopped by itself ("low_storage"), null for a normal Stop.
  String? stopReason;
}

/// Debug-only facts about an audio file, for tests.
class AudioProbeResult {
  AudioProbeResult({required this.durationMs, required this.startHz});

  int durationMs;

  /// Pitch from 0.1 s to 0.35 s (the test tone is 300 Hz + 20 Hz × second).
  double startHz;
}

@HostApi()
abstract class RecorderHostApi {
  EngineSnapshot snapshot();

  /// Asks for the microphone if needed, then starts. Errors: mic_denied
  /// (details "permanent" when Android will not ask again), low_storage, mic_busy.
  @async
  EngineSnapshot start();

  EngineSnapshot pause();

  EngineSnapshot resume();

  @async
  SavedRecording? stop();

  /// Runs off the main thread: the journal fsync must not stall the UI.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  MarkResult mark();

  /// Finalizes recordings left unfinished by a crash; returns them.
  @async
  List<SavedRecording> recover();

  void openAppSettings();

  /// False when the user turned notifications off: recording works, but the lock-screen
  /// Mark / Pause / Stop buttons are hidden. The UI explains this once.
  bool notificationsAllowed();

  /// Folder holding one sub-folder per recording (meta.json, marks.jsonl, audio.m4a, peaks.bin).
  String recordingsRoot();

  /// Copies [startMs, endMs) of `folder/audio.m4a` into a new .m4a in the clip cache
  /// (no re-encode) and returns its path. The source file is only read.
  @async
  String exportClip(String folder, int startMs, int endMs, String fileName);

  /// Debug builds only: duration and test-tone pitch of an audio file.
  @async
  AudioProbeResult probeAudio(String path);

  /// Debug builds only (ignored in release): record a clock-paced test tone instead of
  /// the microphone, for integration tests on emulators whose mic clock is unreliable.
  /// Also keeps the screen on while the test runs.
  void useTestTone(bool on);
}

@FlutterApi()
abstract class RecorderEvents {
  void onSnapshot(EngineSnapshot snapshot);

  /// Any new mark, including ones added outside the app UI (notification, tile).
  void onMark(MarkResult mark);

  /// A recording was saved (from the app, the notification, low storage or recovery).
  void onSaved(SavedRecording recording);
}
