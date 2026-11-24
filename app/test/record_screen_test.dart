import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/record/record_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _app(EngineClient engine, {double textScale = 1, Size size = const Size(390, 844)}) => MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: RecordScreen(services: Services(engine: engine, library: LibraryStore(null), newPlayer: FakePlayer.new)),
      ),
    );

void main() {
  setUpAll(loadTestFonts);

  testWidgets('idle Record screen is labelled and reports engine errors', (tester) async {
    final engine = EngineClient(
      api: FakeHostApi(startError: PlatformException(code: 'mic_busy', message: 'The microphone isn\'t available right now.')),
    );
    await tester.pumpWidget(_app(engine));
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.textContaining('h of space left'), findsOneWidget);
    expect(tester.getSize(find.bySemanticsLabel('Start recording')).width, greaterThanOrEqualTo(48));

    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pumpAndSettle();
    expect(find.text('The microphone isn\'t available right now.'), findsOneWidget);
    engine.dispose();
  });

  testWidgets('microphone refused for good shows the Settings card', (tester) async {
    final engine = EngineClient(
      api: FakeHostApi(startError: PlatformException(code: 'mic_denied', message: 'x', details: 'permanent')),
    );
    await tester.pumpWidget(_app(engine));
    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone is off for Earmark'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Settings'), findsOneWidget);
    engine.dispose();
  });

  testWidgets('record, mark, pause, resume, stop through the screen', (tester) async {
    final api = FakeHostApi();
    final engine = EngineClient(api: api);
    await tester.pumpWidget(_app(engine));
    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pump();
    expect(find.bySemanticsLabel('Recording'), findsOneWidget);

    api.ms = 10000;
    engine.onSnapshot(api.now); // heartbeat
    await tester.pump();
    expect(find.text('00:10'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Bookmark this moment'));
    await tester.pump();
    expect(find.bySemanticsLabel('Mark 1 at 10 seconds'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pause recording'));
    await tester.pump();
    expect(find.bySemanticsLabel('Paused'), findsOneWidget);
    expect(find.bySemanticsLabel('Resume recording'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Resume recording'));
    await tester.pump();
    api.ms = 20000;
    engine.onSnapshot(api.now);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Bookmark this moment'));
    await tester.pump();
    expect(find.bySemanticsLabel('Mark 2 at 20 seconds'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Stop and save'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Saved recording, 00:20 · 2 marks. Open'), findsOneWidget);
    engine.dispose();
  });

  testWidgets('no heartbeat for 1.5 s: the screen stops claiming "Recording"', (tester) async {
    final api = FakeHostApi();
    final engine = EngineClient(api: api);
    await tester.pumpWidget(_app(engine));
    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pump();
    expect(find.bySemanticsLabel('Recording'), findsOneWidget);

    api.silent = true;
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.bySemanticsLabel('Checking microphone…'), findsOneWidget);
    engine.dispose();
  });

  testWidgets('an interruption by a call is named', (tester) async {
    final engine = EngineClient(api: FakeHostApi());
    await tester.pumpWidget(_app(engine));
    engine.onSnapshot(snap(SessionState.interrupted, ms: 5000, why: 'call'));
    await tester.pump();
    expect(find.bySemanticsLabel('Paused: call'), findsOneWidget);
    engine.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('golden: Record idle, dark, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final engine = EngineClient(api: FakeHostApi());
      await tester.pumpWidget(_app(engine, textScale: scale));
      await tester.pump();
      await expectLater(
        find.byType(RecordScreen),
        matchesGoldenFile('goldens/record_idle_dark_x${scale.toStringAsFixed(0)}.png'),
      );
      engine.dispose();
    }, tags: 'golden');

    testWidgets('golden: Record live, dark, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final engine = EngineClient(api: FakeHostApi());
      await tester.pumpWidget(_app(engine, textScale: scale));
      engine.onSnapshot(snap(SessionState.recording, ms: 272000, marks: 3));
      engine.onMark(MarkResult(id: 'a', positionMs: 151000, index: 2));
      engine.onMark(MarkResult(id: 'b', positionMs: 268000, index: 3));
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(RecordScreen),
        matchesGoldenFile('goldens/record_live_dark_x${scale.toStringAsFixed(0)}.png'),
      );
      await tester.pump(const Duration(seconds: 3));
      engine.dispose();
    }, tags: 'golden');
  }

  testWidgets('golden: Record live, landscape', (tester) async {
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = FakeHostApi()
      ..state = SessionState.paused
      ..ms = 95000;
    api.marks.add(MarkResult(id: 'a', positionMs: 42000, index: 1));
    final engine = EngineClient(api: api);
    await tester.pumpWidget(_app(engine, size: const Size(844, 390)));
    await tester.pump();
    engine.onSnapshot(snap(SessionState.paused, ms: 95000, marks: 1));
    engine.onMark(MarkResult(id: 'a', positionMs: 42000, index: 1));
    await tester.pump(const Duration(seconds: 3));
    await expectLater(find.byType(RecordScreen), matchesGoldenFile('goldens/record_live_landscape.png'));
    engine.dispose();
  }, tags: 'golden');
}
