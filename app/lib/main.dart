import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app/design/theme.dart';
import 'app/services.dart';
import 'data/library.dart';
import 'engine/engine_client.dart';
import 'features/playback/player.dart';
import 'features/pro/pro.dart';
import 'features/record/record_screen.dart';

/// Build with `--dart-define=EARMARK_FRAME_LOG=true` (profile) to log frame times every 10 s.
const _frameLog = bool.fromEnvironment('EARMARK_FRAME_LOG');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_frameLog) _logFrames();
  final engine = EngineClient();
  final library = LibraryStore(await engine.recordingsRoot());
  runApp(EarmarkApp(services: Services(engine: engine, library: library, newPlayer: JustAudioPlayer.new, store: IapStore())));
}

class EarmarkApp extends StatefulWidget {
  const EarmarkApp({super.key, required this.services});

  final Services services;

  @override
  State<EarmarkApp> createState() => _EarmarkAppState();
}

class _EarmarkAppState extends State<EarmarkApp> {
  Services get s => widget.services;

  @override
  void initState() {
    super.initState();
    s.engine.lastSaved.addListener(_onSaved);
    _start();
  }

  /// Finish anything a crash left behind, then read the library.
  Future<void> _start() async {
    await s.library.load();
    if ((await s.engine.recover()).isNotEmpty) await s.library.load();
    await s.pro.startup();
  }

  void _onSaved() {
    final r = s.engine.lastSaved.value;
    if (r != null) s.library.upsert(r.folder);
  }

  @override
  void dispose() {
    s.engine.lastSaved.removeListener(_onSaved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Earmark',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: RecordScreen(services: s),
    );
  }
}

/// Frame-time statistics for performance checks (off unless EARMARK_FRAME_LOG is defined).
void _logFrames() {
  final build = <double>[], raster = <double>[];
  SchedulerBinding.instance.addTimingsCallback((frames) {
    for (final f in frames) {
      build.add(f.buildDuration.inMicroseconds / 1000);
      raster.add(f.rasterDuration.inMicroseconds / 1000);
    }
  });
  String stats(List<double> v) {
    final s = [...v]..sort();
    return 'avg ${(s.reduce((a, b) => a + b) / s.length).toStringAsFixed(2)} 99th ${s[((s.length - 1) * 0.99).round()].toStringAsFixed(2)} worst ${s.last.toStringAsFixed(2)} ms';
  }

  Timer.periodic(const Duration(seconds: 10), (_) {
    if (build.isEmpty) return;
    var missed = 0;
    for (var i = 0; i < build.length; i++) {
      if (build[i] > 1000 / 60 || raster[i] > 1000 / 60) missed++; // over a 60 Hz frame budget
    }
    debugPrint('FRAMES n=${build.length} build ${stats(build)}; raster ${stats(raster)}; '
        'over budget $missed (${(100 * missed / build.length).toStringAsFixed(1)} %)');
    build.clear();
    raster.clear();
  });
}
