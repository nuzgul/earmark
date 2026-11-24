// Regression tests for the 2026-11-24 code review: each one reproduces a reported bug.
import 'dart:async';
import 'dart:io';

import 'package:earmark/app/design/sheets.dart';
import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/design/tokens.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/library/library_screen.dart';
import 'package:earmark/features/playback/batch_sheet.dart';
import 'package:earmark/features/playback/clip_sheet.dart';
import 'package:earmark/features/playback/playback_screen.dart';
import 'package:earmark/features/record/record_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Stop and clip export finish only when the test says so.
class _SlowApi extends FakeHostApi {
  int stops = 0;
  final stopDone = Completer<void>();
  final exports = <Completer<String>>[];

  @override
  Future<SavedRecording?> stop() async {
    stops++;
    await stopDone.future;
    return super.stop();
  }

  @override
  Future<String> exportClip(String folder, int startMs, int endMs, String fileName) {
    final c = Completer<String>();
    exports.add(c);
    return c.future;
  }
}

Widget _app(Widget home,
        {Brightness brightness = Brightness.dark, Size size = const Size(390, 844), double text = 1, EdgeInsets insets = EdgeInsets.zero}) =>
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(text), viewInsets: insets),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness), home: home),
    );

void _surface(WidgetTester t, Size size) {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

late Directory _tmp;
late LibraryStore _lib;

Services _services(RecorderHostApi api) => Services(engine: EngineClient(api: api), library: _lib, newPlayer: FakePlayer.new);

/// Lets real file I/O started inside the widget test finish (and its continuations run).
Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
  }
  expect(done(), isTrue, reason: 'file I/O did not finish in 6 s');
}

Future<void> _heartbeat(WidgetTester t, EngineClient e, FakeHostApi api, Duration d) async {
  for (var left = d; left > Duration.zero; left -= const Duration(milliseconds: 250)) {
    e.onSnapshot(api.now);
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(loadTestFonts);

  setUp(() async {
    FakePlayer.failOpen = false;
    _tmp = Directory.systemTemp.createTempSync('earmark-review');
    final root = Directory('${_tmp.path}/recordings')..createSync();
    writeRecording(root.path, 'r1', at: DateTime(2026, 11, 24, 9), durationMs: 120000, marksMs: [30000, 60000, 90000]);
    _lib = LibraryStore(root.path);
    await _lib.load();
  });

  testWidgets('calm screen in the light theme: the timer is light on black', (t) async {
    _surface(t, const Size(390, 844));
    final api = FakeHostApi();
    final s = _services(api);
    await t.pumpWidget(_app(RecordScreen(services: s), brightness: Brightness.light));
    await t.tap(find.bySemanticsLabel('Start recording'));
    await t.pump();
    await _heartbeat(t, s.engine, api, const Duration(seconds: 22));
    final timer = t.widget<Text>(find.text('00:00'));
    expect(timer.style!.color, AppColors.dark.text);
    await t.tap(find.bySemanticsLabel('Bookmark this moment')); // wake
    await t.pump();
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
  });

  testWidgets('two taps on Stop: one save, no false error', (t) async {
    _surface(t, const Size(390, 844));
    final api = _SlowApi();
    final s = _services(api);
    await t.pumpWidget(_app(RecordScreen(services: s)));
    await t.tap(find.bySemanticsLabel('Start recording'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Stop and save'), warnIfMissed: false);
    await t.pump();
    api.stopDone.complete();
    await t.pumpAndSettle();
    expect(api.stops, 1);
    expect(find.textContaining("Couldn't finish saving"), findsNothing);
  });

  testWidgets('two fingers on Bookmark make two marks', (t) async {
    _surface(t, const Size(390, 844));
    final api = FakeHostApi();
    final s = _services(api);
    await t.pumpWidget(_app(RecordScreen(services: s)));
    await t.tap(find.bySemanticsLabel('Start recording'));
    await t.pump();
    final at = t.getCenter(find.bySemanticsLabel('Bookmark this moment'));
    final a = await t.startGesture(at, pointer: 7);
    final b = await t.startGesture(at + const Offset(40, 0), pointer: 8);
    await t.pump();
    await a.up();
    await b.up();
    await t.pump();
    expect(api.marks, hasLength(2));
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
  });

  testWidgets('clip sheet: the first Preview tap shows Stop preview', (t) async {
    _surface(t, const Size(390, 844));
    final r = _lib.byId('r1')!;
    await t.pumpWidget(_app(Scaffold(
      body: ClipSheet(services: _services(FakeHostApi()), recording: r, mark: r.userMarks.first, peaks: Uint8List(0)),
    )));
    await t.tap(find.bySemanticsLabel('Preview'));
    await t.pump();
    expect(find.bySemanticsLabel('Stop preview'), findsOneWidget);
  });

  testWidgets('clip sheet of a recording shorter than a second: nudges do not throw', (t) async {
    _surface(t, const Size(390, 844));
    writeRecording(_lib.root!, 'tiny', at: DateTime(2026, 11, 24, 10), durationMs: 800, marksMs: [400]);
    _lib.upsert('${_lib.root}/tiny');
    final r = _lib.byId('tiny')!;
    await t.pumpWidget(_app(Scaffold(
      body: ClipSheet(services: _services(FakeHostApi()), recording: r, mark: r.userMarks.first, peaks: Uint8List(0)),
    )));
    await t.tap(find.bySemanticsLabel('Start 1 second later'));
    await t.tap(find.bySemanticsLabel('End 1 second earlier'));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('clip sheet fits a small phone at 200 % text', (t) async {
    _surface(t, const Size(360, 640));
    final r = _lib.byId('r1')!;
    await t.pumpWidget(_app(
      Scaffold(body: SingleChildScrollView(child: ClipSheet(services: _services(FakeHostApi()), recording: r, mark: r.userMarks.first, peaks: Uint8List(0)))),
      size: const Size(360, 640),
      text: 2,
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('rename sheet in landscape with the keyboard up: no overflow', (t) async {
    _surface(t, const Size(844, 390));
    await t.pumpWidget(_app(
      Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => askText(context, title: 'Rename', initial: 'x'), child: const Text('go'))))),
      size: const Size(844, 390),
      insets: const EdgeInsets.only(bottom: 200),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('live Record screen fits a small phone at 200 % text', (t) async {
    _surface(t, const Size(360, 640));
    final api = FakeHostApi();
    final s = _services(api);
    await t.pumpWidget(_app(RecordScreen(services: s), size: const Size(360, 640), text: 2));
    await t.tap(find.bySemanticsLabel('Start recording'));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
  });

  testWidgets('batch share: closing the sheet mid-export does not throw', (t) async {
    _surface(t, const Size(390, 844));
    final api = _SlowApi();
    final r = _lib.byId('r1')!;
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      theme: buildTheme(Brightness.dark),
      home: Builder(builder: (context) => Scaffold(body: BatchClipSheet(services: _services(api), recording: r))),
    ));
    await t.tap(find.bySemanticsLabel('Share 3 clips'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: SizedBox())); // the sheet goes away
    api.exports.first.complete('/x/a.m4a');
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('a recording restored from Recently deleted shows again in the Library', (t) async {
    _surface(t, const Size(390, 844));
    final s = _services(FakeHostApi());
    await t.pumpWidget(_app(LibraryScreen(services: s)));
    await t.pump();
    final title = _lib.byId('r1')!.title;
    await t.drag(find.text(title), const Offset(-500, 0));
    await t.pumpAndSettle();
    await _until(t, () => _lib.byId('r1')?.deletedAt != null);
    expect(find.text(title), findsNothing);
    unawaited(_lib.restore('r1')); // as Recently deleted does
    await _until(t, () => _lib.byId('r1')?.deletedAt == null);
    await t.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('Playback: a file that will not open says so instead of failing silently', (t) async {
    _surface(t, const Size(390, 844));
    FakePlayer.failOpen = true;
    await t.pumpWidget(_app(PlaybackScreen(services: _services(FakeHostApi()), recordingId: 'r1')));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Play'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.textContaining("can't be played"), findsOneWidget);
  });

  testWidgets('Playback: dragging across the waveform does not flood the player with seeks', (t) async {
    _surface(t, const Size(390, 844));
    await t.pumpWidget(_app(PlaybackScreen(services: _services(FakeHostApi()), recordingId: 'r1')));
    await t.pump();
    final player = FakePlayer.instances.last;
    final wave = find.bySemanticsLabel('Position');
    final g = await t.startGesture(t.getTopLeft(wave) + const Offset(20, 60));
    for (var i = 0; i < 60; i++) {
      await g.moveBy(const Offset(5, 0));
      await t.pump(const Duration(milliseconds: 8)); // ~120 events a second
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    expect(player.seeks, lessThan(20));
    expect(player.positionMs.value, greaterThan(0), reason: 'still lands where the finger stopped');
  });

  testWidgets('Playback: two quick "+ Mark" taps give two different numbers', (t) async {
    _surface(t, const Size(390, 844));
    await t.pumpWidget(_app(PlaybackScreen(services: _services(FakeHostApi()), recordingId: 'r1')));
    await t.pump();
    await t.tap(find.bySemanticsLabel(RegExp(r'^\+ Mark at')));
    await t.tap(find.bySemanticsLabel(RegExp(r'^\+ Mark at')));
    await _until(t, () => _lib.byId('r1')!.userMarks.length == 5);
    final ns = _lib.byId('r1')!.userMarks.map((m) => m.n).toList();
    expect(ns.toSet().length, ns.length, reason: 'numbers $ns');
  });

  testWidgets('small 320 dp phone: Pause and Stop stay above the Bookmark area with two marks', (t) async {
    _surface(t, const Size(320, 640));
    final api = FakeHostApi();
    final s = _services(api);
    await t.pumpWidget(_app(RecordScreen(services: s), size: const Size(320, 640)));
    await t.tap(find.bySemanticsLabel('Start recording'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await t.pump(const Duration(seconds: 3));
    final stop = t.getRect(find.bySemanticsLabel('Stop and save'));
    final zone = t.getRect(find.bySemanticsLabel('Bookmark this moment'));
    expect(stop.bottom, lessThanOrEqualTo(zone.top), reason: 'Stop $stop, zone $zone');
    expect(t.takeException(), isNull);
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
    expect(api.state, SessionState.idle);
  });

  testWidgets('small 320 dp phone: the playback controls fit', (t) async {
    _surface(t, const Size(320, 640));
    await t.pumpWidget(_app(PlaybackScreen(services: _services(FakeHostApi()), recordingId: 'r1'), size: const Size(320, 640)));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(t.getSize(find.bySemanticsLabel('Next mark')).width, greaterThanOrEqualTo(48));
  });

  group('data', () {
    test('two quick "+ Mark" adds get two numbers and both are kept', () async {
      final m = await Future.wait([_lib.addMark('r1', 15000), _lib.addMark('r1', 45000)]);
      expect(m.map((x) => x.name).toSet(), {'Mark 4', 'Mark 5'});
      final again = LibraryStore(_lib.root);
      await again.load();
      expect(again.byId('r1')!.userMarks, hasLength(5));
    });

    test('quick setting changes all survive', () async {
      await Future.wait([_lib.setCalmMode(false), _lib.setPreRollSeconds(10), _lib.setPro(true), _lib.setPreRoll(false)]);
      final again = LibraryStore(_lib.root);
      await again.load();
      expect((again.calmMode, again.preRollSeconds, again.pro, again.preRoll), (false, 10, true, false));
    });

    test('a damaged library.json is kept aside and its added marks survive the next edit', () async {
      final f = File('${_lib.root}/r1/library.json');
      f.writeAsStringSync('{"added":[{"id":"u1","pos_ms":5000,"n":9}],"labels":{},"deleted":[]}}');
      await _lib.load();
      await _lib.renameMark('r1', 'r1-m1', 'Intro');
      expect(f.readAsStringSync(), contains('"u1"'));
      expect(File('${f.path}.damaged').existsSync(), isTrue);
      expect(_lib.byId('r1')!.userMarks.map((m) => m.name), containsAll(['Intro', 'Mark 9']));
    });

    test('one unreadable folder or odd setting never hides the library', () async {
      final bad = Directory('${_lib.root}/bad')..createSync();
      File('${bad.path}/audio.m4a').writeAsBytesSync([0]);
      File('${bad.path}/meta.json').writeAsStringSync('{"id": 5, "created_at": "x"}');
      File('${Directory(_lib.root!).parent.path}/settings.json').writeAsStringSync('{"pre_roll_s": 5.0, "quick_labels": "Idea"}');
      await _lib.load();
      expect(_lib.byId('r1'), isNotNull);
      expect(_lib.preRollSeconds, 5);
      expect(_lib.quickLabels, LibraryStore.defaultQuickLabels);
    });

    test('day groups count calendar days, also across a DST change', () {
      expect(dayGroup(DateTime(2026, 3, 29, 12), DateTime(2026, 3, 30, 0, 30)), 'Yesterday');
      expect(dayGroup(DateTime(2026, 3, 23, 23, 50), DateTime(2026, 3, 30, 0, 10)), 'Older');
      expect(dayGroup(DateTime(2026, 10, 25, 1), DateTime(2026, 10, 25, 23)), 'Today');
    });

    test('clip file names stay short with a long title and label', () async {
      await _lib.rename('r1', 'A very long recording title ' * 6);
      await _lib.renameMark('r1', 'r1-m1', 'A label that goes on and on ' * 4);
      final r = _lib.byId('r1')!;
      final name = clipFileName(r, r.userMarks.first, 16000, 36000);
      expect(name.length, lessThan(130));
      expect(name, endsWith('.m4a'));
    });
  });
}
