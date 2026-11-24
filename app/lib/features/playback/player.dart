import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// The player the screens use. Widget tests swap in a fake (no platform audio there).
abstract class Player {
  ValueListenable<int> get positionMs;
  ValueListenable<bool> get playing;

  Future<void> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);

  /// Plays exactly [startMs, endMs) once (clip preview).
  Future<void> playRange(int startMs, int endMs);
  Future<void> dispose();
}

class JustAudioPlayer implements Player {
  final _p = AudioPlayer();
  final _position = ValueNotifier(0);
  final _playing = ValueNotifier(false);
  final _subs = <StreamSubscription<Object?>>[];

  JustAudioPlayer() {
    _subs
      ..add(_p.positionStream.listen((d) => _position.value = d.inMilliseconds))
      ..add(_p.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _p.pause(); // stop at the end instead of reporting "playing" forever
        }
        _playing.value = s.playing && s.processingState != ProcessingState.completed;
      }));
    // Headphones unplugged or Bluetooth gone: pause instead of playing out of the speaker.
    AudioSession.instance.then((session) {
      if (_disposed) return;
      _subs.add(session.becomingNoisyEventStream.listen((_) => _p.pause()));
    });
  }

  bool _disposed = false;

  @override
  ValueListenable<int> get positionMs => _position;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  Future<void> open(String path) => _p.setFilePath(path);

  @override
  Future<void> play() async {
    if (_p.processingState == ProcessingState.completed) await _p.seek(Duration.zero);
    unawaited(_p.play()); // completes only when playback stops
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(int ms) => _p.seek(Duration(milliseconds: ms));

  @override
  Future<void> playRange(int startMs, int endMs) async {
    await _p.setClip(start: Duration(milliseconds: startMs), end: Duration(milliseconds: endMs));
    await _p.seek(Duration.zero);
    unawaited(_p.play());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await _p.dispose();
  }
}
