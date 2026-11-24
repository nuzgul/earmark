import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:earmark/features/playback/player.dart';
import 'package:flutter/foundation.dart';

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

  @override
  ValueListenable<int> get positionMs => _pos;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<void> open(String path) async => opened = path;

  @override
  Future<void> play() async => _playing.value = true;

  @override
  Future<void> pause() async => _playing.value = false;

  @override
  Future<void> seek(int ms) async => _pos.value = ms;

  @override
  Future<void> playRange(int startMs, int endMs) async {
    range = (start: startMs, end: endMs);
    _playing.value = true;
  }

  @override
  Future<void> dispose() async {}
}
