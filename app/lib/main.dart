import 'package:flutter/material.dart';

import 'app/design/theme.dart';
import 'app/services.dart';
import 'data/library.dart';
import 'engine/engine_client.dart';
import 'features/playback/player.dart';
import 'features/pro/pro.dart';
import 'features/record/record_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
