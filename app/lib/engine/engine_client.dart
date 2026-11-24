import 'dart:async';

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
    EngineSnapshot(state: SessionState.idle, positionMs: 0, level: 0, markCount: 0, freeBytes: 0),
  );

  /// Marks of the session in progress, oldest first (from the app, notification or tile).
  final marks = ValueNotifier<List<MarkResult>>(const []);

  /// True when a session is active but no heartbeat came for 1.5 s: the UI then says
  /// "Checking microphone…" instead of "Recording".
  final stale = ValueNotifier(false);

  /// The most recent recording saved or recovered.
  final lastSaved = ValueNotifier<SavedRecording?>(null);

  static const _staleAfter = Duration(milliseconds: 1500);
  Timer? _watchdog;

  bool get _active => snapshot.value.state != SessionState.idle;

  /// Asks the engine for its state; keeps the last known one if the engine is absent
  /// (iOS until Phase 3).
  Future<void> refresh() async {
    try {
      _apply(await _api.snapshot());
    } on PlatformException {
      // No engine on this platform yet: stay idle.
    }
  }

  /// Finishes recordings a crash left behind; the newest becomes [lastSaved].
  Future<List<SavedRecording>> recover() async {
    try {
      final found = await _api.recover();
      if (found.isNotEmpty) {
        lastSaved.value = found.reduce((a, b) => a.createdAtMs > b.createdAtMs ? a : b);
      }
      return found;
    } on PlatformException {
      return const [];
    }
  }

  /// Null on success; otherwise the engine's error (code mic_denied, low_storage, mic_busy...).
  Future<PlatformException?> start() async {
    try {
      _apply(await _api.start());
      return null;
    } on PlatformException catch (e) {
      return e;
    }
  }

  Future<void> pause() async => _apply(await _api.pause());

  Future<void> resume() async => _apply(await _api.resume());

  /// The new mark, or null if nothing is recording any more.
  Future<MarkResult?> mark() async {
    try {
      final m = await _api.mark();
      _addMark(m);
      return m;
    } on PlatformException {
      return null;
    }
  }

  /// The saved recording, or null if saving failed (the engine retries on next launch).
  Future<SavedRecording?> stop() async {
    SavedRecording? saved;
    try {
      saved = await _api.stop();
    } on PlatformException {
      saved = null; // the engine keeps the audio and finishes it on the next launch
    }
    if (saved != null) lastSaved.value = saved;
    await refresh();
    return saved;
  }

  Future<void> openAppSettings() => _api.openAppSettings();

  /// False only when the engine says notifications are off (the lock-screen buttons are hidden).
  Future<bool> notificationsAllowed() async {
    try {
      return await _api.notificationsAllowed();
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Where recordings live; null when this platform has no engine yet (iOS before Phase 3).
  Future<String?> recordingsRoot() async {
    try {
      return await _api.recordingsRoot();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Lossless clip of [folder]'s audio; returns the new file's path. Throws PlatformException.
  Future<String> exportClip(String folder, int startMs, int endMs, String fileName) =>
      _api.exportClip(folder, startMs, endMs, fileName);

  /// Integration tests only (debug builds): duration and test-tone pitch of a file.
  @visibleForTesting
  Future<AudioProbeResult> probeAudio(String path) => _api.probeAudio(path);

  /// Integration tests only; the engine ignores it in release builds.
  @visibleForTesting
  Future<void> useTestTone(bool on) => _api.useTestTone(on);

  void dispose() {
    _watchdog?.cancel();
    RecorderEvents.setUp(null);
  }

  void _apply(EngineSnapshot s) {
    if (s.recordingId != snapshot.value.recordingId) marks.value = const [];
    snapshot.value = s;
    stale.value = false;
    _watchdog?.cancel();
    if (_active) _watchdog = Timer(_staleAfter, _onSilence);
  }

  void _onSilence() {
    stale.value = true;
    refresh();
    if (_active) _watchdog = Timer(_staleAfter, _onSilence);
  }

  void _addMark(MarkResult m) {
    if (marks.value.any((e) => e.id == m.id)) return; // reply and event both carry it
    marks.value = [...marks.value, m]..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  void onSnapshot(EngineSnapshot s) => _apply(s);

  @override
  void onMark(MarkResult mark) => _addMark(mark);

  @override
  void onSaved(SavedRecording recording) => lastSaved.value = recording;
}
