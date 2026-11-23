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
enum SessionState { idle, starting, recording, paused, interrupted, finalizing }

/// Sent on every heartbeat (about every 250 ms) and after every command.
class EngineSnapshot {
  EngineSnapshot({
    required this.state,
    required this.positionMs,
    required this.level,
    required this.markCount,
  });

  SessionState state;

  /// Folder id of the recording in progress, null when idle.
  String? recordingId;

  /// Audio actually captured, paused time excluded (frame-counted).
  int positionMs;

  /// Smoothed input level, 0.0 to 1.0.
  double level;

  int markCount;

  /// Why capture is interrupted: "call", "mic_lost", "low_storage". Null otherwise.
  String? interruption;
}

class MarkResult {
  MarkResult({required this.id, required this.positionMs, required this.index});

  String id;

  /// Frame-counted position of the mark in the saved audio.
  int positionMs;

  /// 1-based number used for the automatic name "Mark N".
  int index;
}

@HostApi()
abstract class RecorderHostApi {
  EngineSnapshot snapshot();

  @async
  EngineSnapshot start();

  EngineSnapshot pause();

  EngineSnapshot resume();

  @async
  EngineSnapshot stop();

  MarkResult mark();
}

@FlutterApi()
abstract class RecorderEvents {
  void onSnapshot(EngineSnapshot snapshot);

  /// A mark added outside the app UI (notification, tile, Live Activity).
  void onMark(MarkResult mark);
}
