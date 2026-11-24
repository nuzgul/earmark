import '../data/library.dart';
import '../engine/engine_client.dart';
import '../features/playback/player.dart';
import '../features/pro/pro.dart';

/// What the screens need, passed down explicitly (tests build it from fakes).
class Services {
  Services({required this.engine, required this.library, required this.newPlayer, Store? store})
      : pro = Pro(store: store ?? NoStore(), library: library);

  final EngineClient engine;
  final LibraryStore library;
  final Player Function() newPlayer;
  final Pro pro;
}
