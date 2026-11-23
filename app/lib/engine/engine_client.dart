import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine_api.g.dart';

/// The UI's only view of the native engine. [snapshot] always holds what the engine
/// last reported, so the screen cannot claim a state the engine is not in.
class EngineClient implements RecorderEvents {
  EngineClient({RecorderHostApi? api}) : _api = api ?? RecorderHostApi() {
    RecorderEvents.setUp(this);
  }

  final RecorderHostApi _api;

  final snapshot = ValueNotifier(
    EngineSnapshot(state: SessionState.idle, positionMs: 0, level: 0, markCount: 0),
  );

  /// Asks the engine for its state; keeps the last known one if the engine is absent
  /// (iOS until Phase 3).
  Future<void> refresh() async {
    try {
      snapshot.value = await _api.snapshot();
    } on PlatformException {
      // No engine on this platform yet: stay idle.
    }
  }

  /// Returns null on success, or a message for the user.
  Future<String?> start() => _run(_api.start);

  Future<String?> _run(Future<EngineSnapshot> Function() call) async {
    try {
      snapshot.value = await call();
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'Recording could not start.';
    }
  }

  @override
  void onSnapshot(EngineSnapshot s) => snapshot.value = s;

  @override
  void onMark(MarkResult mark) {} // Phase 1: show marks added from the notification.
}
