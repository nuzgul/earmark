import 'dart:async';
import 'dart:io';

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

EngineSnapshot _snap(SessionState state, {int ms = 0, int marks = 0, String? why}) => EngineSnapshot(
      state: state,
      recordingId: state == SessionState.idle ? null : 'rec-1',
      positionMs: ms,
      level: 0.6,
      markCount: marks,
      interruption: why,
      freeBytes: 2 << 30,
    );

/// Engine double that behaves like the Android engine, minus the audio.
class _FakeApi extends RecorderHostApi {
  _FakeApi({this.startError});

  final PlatformException? startError;
  var state = SessionState.idle;
  var ms = 0;
  final marks = <MarkResult>[];

  /// The engine stops answering (process frozen, bridge gone).
  bool silent = false;

  EngineSnapshot get now => _snap(state, ms: ms, marks: marks.length);

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

Widget _app(EngineClient engine, {double textScale = 1, Size size = const Size(390, 844)}) => MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: RecordScreen(services: Services(engine: engine, library: LibraryStore(null), newPlayer: FakePlayer.new)),
      ),
    );

void main() {
  setUpAll(() async {
    // Widget tests do not load bundled fonts by themselves.
    final loader = FontLoader('MonaSans')
      ..addFont(File('assets/fonts/MonaSans-Variable.ttf').readAsBytes().then(ByteData.sublistView));
    await loader.load();
    // Icons too, so goldens show real glyphs instead of boxes.
    // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('$artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then(ByteData.sublistView));
    await icons.load();
  });

  testWidgets('idle Record screen is labelled and reports engine errors', (tester) async {
    final engine = EngineClient(
      api: _FakeApi(startError: PlatformException(code: 'mic_busy', message: 'The microphone isn\'t available right now.')),
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
      api: _FakeApi(startError: PlatformException(code: 'mic_denied', message: 'x', details: 'permanent')),
    );
    await tester.pumpWidget(_app(engine));
    await tester.tap(find.bySemanticsLabel('Start recording'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone is off for Earmark'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Settings'), findsOneWidget);
    engine.dispose();
  });

  testWidgets('record, mark, pause, resume, stop through the screen', (tester) async {
    final api = _FakeApi();
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
    final api = _FakeApi();
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
    final engine = EngineClient(api: _FakeApi());
    await tester.pumpWidget(_app(engine));
    engine.onSnapshot(_snap(SessionState.interrupted, ms: 5000, why: 'call'));
    await tester.pump();
    expect(find.bySemanticsLabel('Paused: call'), findsOneWidget);
    engine.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('golden: Record idle, dark, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final engine = EngineClient(api: _FakeApi());
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
      final engine = EngineClient(api: _FakeApi());
      await tester.pumpWidget(_app(engine, textScale: scale));
      engine.onSnapshot(_snap(SessionState.recording, ms: 272000, marks: 3));
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
    final api = _FakeApi()
      ..state = SessionState.paused
      ..ms = 95000;
    api.marks.add(MarkResult(id: 'a', positionMs: 42000, index: 1));
    final engine = EngineClient(api: api);
    await tester.pumpWidget(_app(engine, size: const Size(844, 390)));
    await tester.pump();
    engine.onSnapshot(_snap(SessionState.paused, ms: 95000, marks: 1));
    engine.onMark(MarkResult(id: 'a', positionMs: 42000, index: 1));
    await tester.pump(const Duration(seconds: 3));
    await expectLater(find.byType(RecordScreen), matchesGoldenFile('goldens/record_live_landscape.png'));
    engine.dispose();
  }, tags: 'golden');
}
