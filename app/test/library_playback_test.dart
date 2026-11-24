import 'dart:io';

import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/library/library_screen.dart';
import 'package:earmark/features/playback/clip_sheet.dart';
import 'package:earmark/features/playback/playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class _Api extends RecorderHostApi {
  final clips = <(int, int, String)>[];

  @override
  Future<EngineSnapshot> snapshot() async =>
      EngineSnapshot(state: SessionState.idle, positionMs: 0, level: 0, markCount: 0, freeBytes: 1 << 30);

  @override
  Future<String> exportClip(String folder, int startMs, int endMs, String fileName) async {
    clips.add((startMs, endMs, fileName));
    return '$folder/$fileName';
  }
}

final now = DateTime(2026, 11, 24, 15, 0);
late Directory tmp;
late LibraryStore lib;
late Services services;

Widget _app(Widget home, {Brightness brightness = Brightness.dark, double textScale = 1}) => MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness), home: home),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('MonaSans')
      ..addFont(File('assets/fonts/MonaSans-Variable.ttf').readAsBytes().then(ByteData.sublistView));
    await loader.load();
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('$artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then(ByteData.sublistView));
    await icons.load();
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('earmark');
    final root = Directory('${tmp.path}/recordings')..createSync(); // settings.json goes next to it
    writeRecording(root.path, 'rehearsal', at: now.subtract(const Duration(hours: 2)), durationMs: 312000, marksMs: [42000, 151000, 272000], callAtMs: 200000);
    writeRecording(root.path, 'lecture', at: now.subtract(const Duration(days: 1, hours: 3)), durationMs: 3125000, marksMs: [600000]);
    writeRecording(root.path, 'idea', at: now.subtract(const Duration(days: 12)), durationMs: 41000);
    lib = LibraryStore(root.path, now: () => now);
    await lib.load();
    // Edits write files asynchronously; done here, outside the widget tests' fake clock.
    await lib.rename('rehearsal', 'Pitch rehearsal');
    await lib.rename('lecture', 'Lecture 7 · Thermodynamics');
    await lib.renameMark('rehearsal', 'rehearsal-m2', 'Second verse');
    FakePlayer.instances.clear();
    services = Services(engine: EngineClient(api: _Api()), library: lib, newPlayer: FakePlayer.new);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('library groups by day and shows mark counts', (t) async {
    await t.pumpWidget(_app(LibraryScreen(services: services)));
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('OLDER'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Pitch rehearsal, 13:00 · 05:12, 3 marks$')), findsOneWidget);
  });

  testWidgets('search finds a mark by time and opens it with pre-roll', (t) async {
    await t.pumpWidget(_app(LibraryScreen(services: services)));
    await t.enterText(find.byType(TextField), '04:32');
    await t.pump();
    expect(find.text('MATCHING MARKS'), findsOneWidget);
    await t.tap(find.bySemanticsLabel(RegExp('^Mark 3 at 4 minutes 32 seconds')));
    await t.pumpAndSettle();
    expect(find.byType(PlaybackScreen), findsOneWidget);
    final p = FakePlayer.instances.single;
    expect(p.positionMs.value, 272000 - 3000);
    expect(p.playing.value, isTrue);
  });

  testWidgets('playback: flags jump, next/previous mark, pre-roll off', (t) async {
    _phone(t);
    await t.pumpWidget(_app(PlaybackScreen(services: services, recordingId: 'rehearsal')));
    await t.pump();
    final p = FakePlayer.instances.single;
    expect(p.opened, endsWith('rehearsal/audio.m4a'));

    await t.tap(find.bySemanticsLabel('Second verse at 2 minutes 31 seconds, jump'));
    expect(p.positionMs.value, 148000);
    await t.tap(find.bySemanticsLabel('Next mark'));
    expect(p.positionMs.value, 269000);
    await t.tap(find.bySemanticsLabel('Previous mark'));
    expect(p.positionMs.value, 148000);

    await t.runAsync(() => lib.setPreRoll(false));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Play from Mark 1 at 42 seconds'));
    expect(p.positionMs.value, 42000);
  });

  testWidgets('clip sheet: 14 s before + 6 s after, nudges, exact preview, export name', (t) async {
    _phone(t);
    final r = lib.byId('rehearsal')!;
    final m = r.userMarks.last; // 04:32
    await t.pumpWidget(_app(Scaffold(body: ClipSheet(services: services, recording: r, mark: m, peaks: File(r.peaksPath).readAsBytesSync()))));
    expect(find.text('04:18 → 04:38 · 20.0 s'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Start 1 second earlier'));
    await t.tap(find.bySemanticsLabel('End 1 second later'));
    await t.pump();
    expect(find.text('04:17 → 04:39 · 22.0 s'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Preview'));
    await t.pump();
    expect(FakePlayer.instances.single.range, (start: 257000, end: 279000));
  });

  for (final b in Brightness.values) {
    testWidgets('golden: library ${b.name}', (t) async {
      _phone(t);
      await t.pumpWidget(_app(LibraryScreen(services: services), brightness: b));
      await expectLater(find.byType(LibraryScreen), matchesGoldenFile('goldens/library_${b.name}.png'));
    }, tags: 'golden');

    testWidgets('golden: playback ${b.name}', (t) async {
      _phone(t);
      await t.pumpWidget(_app(PlaybackScreen(services: services, recordingId: 'rehearsal'), brightness: b));
      await t.pump();
      await FakePlayer.instances.single.seek(151000 - 3000);
      await t.pump();
      await expectLater(find.byType(PlaybackScreen), matchesGoldenFile('goldens/playback_${b.name}.png'));
    }, tags: 'golden');

    testWidgets('golden: clip sheet ${b.name}', (t) async {
      _phone(t);
      final r = lib.byId('rehearsal')!;
      await t.pumpWidget(_app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: buildTheme(b).colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
                child: ClipSheet(services: services, recording: r, mark: r.userMarks.last, peaks: File(r.peaksPath).readAsBytesSync()),
              ),
            ),
          ),
        ),
        brightness: b,
      ));
      await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/clip_sheet_${b.name}.png'));
    }, tags: 'golden');
  }

  testWidgets('golden: playback at 200 % text', (t) async {
    _phone(t);
    await t.pumpWidget(_app(PlaybackScreen(services: services, recordingId: 'rehearsal'), textScale: 2));
    await t.pump();
    await expectLater(find.byType(PlaybackScreen), matchesGoldenFile('goldens/playback_dark_x2.png'));
  }, tags: 'golden');
}
