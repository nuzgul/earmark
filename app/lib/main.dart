import 'package:flutter/material.dart';

import 'app/design/theme.dart';
import 'engine/engine_client.dart';
import 'features/record/record_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EarmarkApp(engine: EngineClient()));
}

class EarmarkApp extends StatelessWidget {
  const EarmarkApp({super.key, required this.engine});

  final EngineClient engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Earmark',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark, // recording happens in the dark theme; light follows in Phase 2
      home: RecordScreen(engine: engine),
    );
  }
}
