import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Writes a recording folder the way the Android engine does (audio is a placeholder byte;
/// peaks.bin is a speech-like envelope so goldens show a real-looking waveform).
void writeRecording(String root, String id,
    {required DateTime at, int durationMs = 60000, List<int> marksMs = const [], int? callAtMs}) {
  final d = Directory('$root/$id')..createSync(recursive: true);
  File('${d.path}/audio.m4a').writeAsBytesSync([0]);
  File('${d.path}/meta.json').writeAsStringSync(jsonEncode({
    'id': id,
    'created_at': at.millisecondsSinceEpoch,
    'sample_rate': 48000,
    'channels': 1,
    'bitrate': 96000,
    'status': 'saved',
    'duration_ms': durationMs,
    'stop_reason': null,
  }));
  final lines = [
    for (final (i, ms) in marksMs.indexed)
      jsonEncode({'id': '$id-m${i + 1}', 'pos_frames': ms * 48, 'sample_rate': 48000, 'created_at': 0, 'source': 'app', 'kind': 'user'}),
    if (callAtMs != null)
      jsonEncode({'id': '$id-call', 'pos_frames': callAtMs * 48, 'sample_rate': 48000, 'created_at': 0, 'source': 'system', 'kind': 'system', 'note': 'call'}),
  ];
  File('${d.path}/marks.jsonl').writeAsStringSync('${lines.join('\n')}\n{"id":"torn","pos_fr');
  final rnd = math.Random(id.hashCode);
  File('${d.path}/peaks.bin').writeAsBytesSync([
    for (var i = 0; i < durationMs ~/ 50; i++)
      (math.pow(math.sin(i / 9).abs(), 2) * 150 + rnd.nextInt(60) + (i % 37 < 6 ? 0 : 20)).clamp(0, 255).toInt(),
  ]);
}

/// Player double: records what the screens asked for; no platform audio in widget tests.
class FakePlayer implements Player {
  static final instances = <FakePlayer>[];

  FakePlayer() {
    instances.add(this);
  }

  final _pos = ValueNotifier(0);
  final _playing = ValueNotifier(false);
  String? opened;
  ({int start, int end})? range;
  int seeks = 0;

  /// The next players fail to open their file (missing or damaged audio).
  static bool failOpen = false;

  @override
  ValueListenable<int> get positionMs => _pos;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<void> open(String path) async {
    if (failOpen) throw Exception('cannot open $path');
    opened = path;
  }

  @override
  Future<void> play() async => _playing.value = true;

  @override
  Future<void> pause() async => _playing.value = false;

  @override
  Future<void> seek(int ms) async {
    seeks++;
    _pos.value = ms;
  }

  double speed = 1;

  @override
  Future<void> setSpeed(double s) async => speed = s;

  @override
  Future<void> playRange(int startMs, int endMs) async {
    range = (start: startMs, end: endMs);
    _playing.value = true;
  }

  @override
  Future<void> dispose() async {}
}

EngineSnapshot snap(SessionState state, {int ms = 0, int marks = 0, String? why}) => EngineSnapshot(
      state: state,
      recordingId: state == SessionState.idle ? null : 'rec-1',
      positionMs: ms,
      level: 0.6,
      markCount: marks,
      interruption: why,
      freeBytes: 2 << 30,
    );

/// Engine double that behaves like the Android engine, minus the audio.
class FakeHostApi extends RecorderHostApi {
  FakeHostApi({this.startError});

  final PlatformException? startError;
  var state = SessionState.idle;
  var ms = 0;
  final marks = <MarkResult>[];

  /// The engine stops answering (process frozen, bridge gone).
  bool silent = false;

  EngineSnapshot get now => snap(state, ms: ms, marks: marks.length);

  @override
  Future<EngineSnapshot> snapshot() => silent ? Completer<EngineSnapshot>().future : Future.value(now);

  @override
  Future<List<SavedRecording>> recover() async => const [];

  @override
  Future<EngineSnapshot> start() async {
    if (startError != null) throw startError!;
    state = SessionState.recording;
    return now;
  }

  @override
  Future<EngineSnapshot> pause() async {
    state = SessionState.paused;
    return now;
  }

  @override
  Future<EngineSnapshot> resume() async {
    state = SessionState.recording;
    return now;
  }

  @override
  Future<MarkResult> mark() async {
    final m = MarkResult(id: 'm${marks.length + 1}', positionMs: ms, index: marks.length + 1);
    marks.add(m);
    return m;
  }

  @override
  Future<SavedRecording?> stop() async {
    state = SessionState.idle;
    return SavedRecording(id: 'rec-1', folder: '/x', createdAtMs: 0, durationMs: ms, marks: marks, recovered: false);
  }
}

/// Widget tests do not load bundled fonts by themselves; icons too, so goldens show real glyphs.
Future<void> loadTestFonts() async {
  final loader = FontLoader('MonaSans')
    ..addFont(File('assets/fonts/MonaSans-Variable.ttf').readAsBytes().then(ByteData.sublistView));
  await loader.load();
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('$artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then(ByteData.sublistView));
  await icons.load();
}
