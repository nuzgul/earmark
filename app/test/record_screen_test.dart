import 'dart:io';

import 'package:earmark/app/design/theme.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/record/record_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Engine double: idle, and start() fails the way the Phase 0 Android stub does.
class _PendingApi extends RecorderHostApi {
  @override
  Future<EngineSnapshot> snapshot() async =>
      EngineSnapshot(state: SessionState.idle, positionMs: 0, level: 0, markCount: 0);

  @override
  Future<EngineSnapshot> start() async =>
      throw PlatformException(code: 'engine_not_ready', message: 'Recording is not built yet.');
}

Widget _app({double textScale = 1}) => MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: RecordScreen(engine: EngineClient(api: _PendingApi())),
      ),
    );

void main() {
  setUpAll(() async {
    // Widget tests do not load bundled fonts by themselves.
    final loader = FontLoader('MonaSans')
      ..addFont(File('assets/fonts/MonaSans-Variable.ttf').readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  testWidgets('idle Record screen is labelled and reports engine errors', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.bySemanticsLabel('Start recording'), findsOneWidget);

    final button = tester.getSize(find.bySemanticsLabel('Start recording'));
    expect(button.width, greaterThanOrEqualTo(48));

    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pumpAndSettle();
    expect(find.text('Recording is not built yet.'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('golden: Record idle, dark, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(textScale: scale));
      await tester.pump();
      await expectLater(
        find.byType(RecordScreen),
        matchesGoldenFile('goldens/record_idle_dark_x${scale.toStringAsFixed(0)}.png'),
      );
    }, tags: 'golden');
  }
}
