import '../data/library.dart';
import '../engine/engine_client.dart';
import '../features/playback/player.dart';

/// What the screens need, passed down explicitly (tests build it from fakes).
class Services {
  const Services({required this.engine, required this.library, required this.newPlayer});

  final EngineClient engine;
  final LibraryStore library;
  final Player Function() newPlayer;
}
