// "Make it expensive" and accessibility checks that a widget test can measure
// (docs/ui-premium/AUDIT-expensive-2026-11-24.md).
import 'dart:io';

import 'package:earmark/app/design/sheets.dart';
import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/library/library_screen.dart';
import 'package:earmark/features/playback/playback_screen.dart';
import 'package:earmark/features/pro/pro.dart';
import 'package:earmark/features/record/record_screen.dart';
import 'package:earmark/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _app(Widget home, {MediaQueryData media = const MediaQueryData(size: Size(390, 844))}) => MediaQuery(
      data: media,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: home),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

/// Counts haptic calls sent to the platform.
List<String> _haptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

Future<(FakeHostApi, EngineClient)> _recording(WidgetTester t, {MediaQueryData? media}) async {
  final api = FakeHostApi();
  final engine = EngineClient(api: api);
  final s = Services(engine: engine, library: LibraryStore(null), newPlayer: FakePlayer.new);
  await t.pumpWidget(_app(RecordScreen(services: s), media: media ?? const MediaQueryData(size: Size(390, 844))));
  await t.tap(find.bySemanticsLabel('Start recording'));
  await t.pump();
  return (api, engine);
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('A1 + A5: Bookmark reacts on touch-down, in the same frame as one haptic and the mark', (t) async {
    _phone(t);
    final haptics = _haptics(t);
    final (api, engine) = await _recording(t);
    haptics.clear();

    final g = await t.startGesture(t.getCenter(find.bySemanticsLabel('Bookmark this moment')));
    await t.pump(); // one frame, finger still down
    final scale = t.widget<AnimatedScale>(
      find.descendant(of: find.bySemanticsLabel('Bookmark this moment'), matching: find.byType(AnimatedScale)).first,
    );
    expect(scale.scale, 0.97, reason: 'pressed state starts on touch-down');
    expect(scale.duration, const Duration(milliseconds: 90), reason: 'press-in token, well under 100 ms');
    expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: 'one haptic, on the same frame');
    expect(api.marks, hasLength(1), reason: 'the mark goes out on touch-down, not on release');
    await g.up();
    await t.pump();

    await t.tap(find.bySemanticsLabel('Pause recording'));
    await t.pump();
    expect(haptics, hasLength(1), reason: 'no haptic on an ordinary tap');
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
    expect(haptics.last, 'HapticFeedbackType.lightImpact', reason: 'saved: a job finished');
    engine.dispose();
  });

  testWidgets('B9: reduced motion makes press and calm changes instant', (t) async {
    _phone(t);
    _haptics(t);
    final (_, engine) = await _recording(t, media: const MediaQueryData(size: Size(390, 844), disableAnimations: true));
    final g = await t.startGesture(t.getCenter(find.bySemanticsLabel('Bookmark this moment')));
    await t.pump();
    final scale = t.widget<AnimatedScale>(
      find.descendant(of: find.bySemanticsLabel('Bookmark this moment'), matching: find.byType(AnimatedScale)).first,
    );
    expect(scale.duration, Duration.zero);
    await g.up();
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
    engine.dispose();
  });

  testWidgets('screen reader on: the calm screen never dims or swallows a touch', (t) async {
    _phone(t);
    final (api, engine) = await _recording(t, media: const MediaQueryData(size: Size(390, 844), accessibleNavigation: true));
    for (var i = 0; i < 90; i++) {
      engine.onSnapshot(api.now);
      await t.pump(const Duration(milliseconds: 250));
    }
    final pill = find.ancestor(of: find.bySemanticsLabel('Recording'), matching: find.byType(AnimatedOpacity)).first;
    expect(t.widget<AnimatedOpacity>(pill).opacity, 1);
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await t.pumpAndSettle();
    expect(engine.snapshot.value.state.name, 'idle');
    engine.dispose();
  });

  for (final (name, sheet) in [
    ('Settings', (Services s) => SettingsSheet(services: s)),
    ('Pro', (Services s) => ProSheet(pro: s.pro)),
  ]) {
    testWidgets('$name sheet fits at 200 % text', (t) async {
      _phone(t);
      final s = Services(engine: EngineClient(api: FakeHostApi()), library: LibraryStore(null), newPlayer: FakePlayer.new);
      await t.pumpWidget(_app(
        Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: sheet(s)))),
        media: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(2)),
      ));
      await t.pump();
      expect(t.takeException(), isNull, reason: 'no overflow');
    });
  }

  group('B1 + B7 on Playback', () {
    late LibraryStore lib;
    setUp(() async {
      final tmp = Directory.systemTemp.createTempSync('earmark-b1');
      final root = Directory('${tmp.path}/recordings')..createSync();
      writeRecording(root.path, 'r1', at: DateTime(2026, 11, 24, 9), durationMs: 120000, marksMs: [30000, 60000, 90000]);
      lib = LibraryStore(root.path);
      await lib.load();
      trackLastTouch();
    });

    Future<void> open(WidgetTester t, {bool reduced = false}) async {
      _phone(t);
      final s = Services(engine: EngineClient(api: FakeHostApi()), library: lib, newPlayer: FakePlayer.new);
      await t.pumpWidget(_app(PlaybackScreen(services: s, recordingId: 'r1'),
          media: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced)));
      await t.pump();
    }

    testWidgets('B1: a mark menu opens at the control that asked for it, not as a bottom sheet', (t) async {
      await open(t);
      final more = t.getCenter(find.bySemanticsLabel('More for Mark 2'));
      await t.tapAt(more);
      await t.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      expect(find.byType(BottomSheet), findsNothing);
      final item = t.getRect(find.text('Delete mark'));
      expect((item.center.dy - more.dy).abs(), lessThan(160), reason: 'menu next to the ⋯ at $more, item at $item');
      await t.tapAt(const Offset(20, 20)); // outside: it closes back
      await t.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
    });

    testWidgets('B7: a deleted mark row slides out before the gap closes, then Undo is offered', (t) async {
      await open(t);
      await t.tapAt(t.getCenter(find.bySemanticsLabel('More for Mark 2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete mark'));
      await t.pump();
      // Every 20 ms: Mark 2 slides and fades while Mark 3 holds still; once Mark 2 is gone, Mark 3
      // rises into the gap in small steps (no jump), the "neighbours pushed smoothly" of B7.
      double fade() => t.widget<Opacity>(find.ancestor(of: find.text('Mark 2'), matching: find.byType(Opacity)).first).opacity;
      final y0 = t.getTopLeft(find.text('Mark 3')).dy;
      final samples = <String>[];
      var lastY = y0, sawMid = false;
      for (var ms = 20; ms <= 340; ms += 20) {
        await t.pump(const Duration(milliseconds: 20));
        final y = t.getTopLeft(find.text('Mark 3')).dy, o = fade();
        sawMid |= o > 0 && o < 1;
        samples.add('${ms}ms o=${o.toStringAsFixed(2)} up=${(y0 - y).toStringAsFixed(1)}');
        expect(y, lessThanOrEqualTo(lastY), reason: 'Mark 3 only moves up');
        expect(lastY - y, lessThan(12), reason: 'no jump between frames $samples');
        if (o > 0) expect(y, y0, reason: 'while the row is still visible its neighbour holds still $samples');
        lastY = y;
      }
      expect(sawMid, isTrue, reason: 'the row fades, it does not blink out $samples');
      expect(y0 - lastY, greaterThan(40), reason: 'Mark 3 took the place of the deleted row $samples');
      // ignore: avoid_print
      print('B7 per 20 ms frame: $samples');
      for (var i = 0; i < 100 && lib.byId('r1')!.userMarks.length == 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Mark 2'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('B9: with reduced motion the menu and the row change at once', (t) async {
      await open(t, reduced: true);
      await t.tapAt(t.getCenter(find.bySemanticsLabel('More for Mark 2')));
      await t.pump();
      expect(find.text('Delete mark'), findsOneWidget, reason: 'no opening animation');
      await t.pumpAndSettle(); // the route takes taps once its (zero-length) opening has completed
      await t.tap(find.text('Delete mark'));
      await t.pump();
      for (var i = 0; i < 100 && lib.byId('r1')!.userMarks.length == 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pump();
      expect(lib.byId('r1')!.userMarks.length, 2, reason: 'the mark was deleted');
      expect(find.text('Mark 2'), findsNothing);
    });
  });

  group('B7 in Library', () {
    late LibraryStore lib;
    setUp(() async {
      final tmp = Directory.systemTemp.createTempSync('earmark-b7');
      final root = Directory('${tmp.path}/recordings')..createSync();
      for (final h in [9, 10, 11]) {
        writeRecording(root.path, 'r$h', at: DateTime(2026, 11, 24, h));
      }
      lib = LibraryStore(root.path);
      await lib.load();
      trackLastTouch();
    });

    testWidgets('Delete from the menu: the row slides out, then the rows below glide up, no jump at the end', (t) async {
      _phone(t);
      final s = Services(engine: EngineClient(api: FakeHostApi()), library: lib, newPlayer: FakePlayer.new);
      await t.pumpWidget(_app(LibraryScreen(services: s)));
      await t.pump();
      final top = lib.byId('r11')!.title, next = lib.byId('r10')!.title;
      final below = find.text(next);
      final y0 = t.getTopLeft(below).dy;
      await t.tapAt(t.getCenter(find.bySemanticsLabel('More for $top')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pump();
      var lastY = y0;
      for (var ms = 20; ms <= 340; ms += 20) {
        await t.pump(const Duration(milliseconds: 20));
        final y = t.getTopLeft(below).dy;
        expect(y, lessThanOrEqualTo(lastY), reason: 'the next row only moves up');
        expect(lastY - y, lessThan(16), reason: 'no jump between frames');
        lastY = y;
      }
      expect(y0 - lastY, greaterThan(40), reason: 'the next row took the place of the deleted one');
      for (var i = 0; i < 100 && lib.recordings.length == 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pump();
      expect(lib.recordings.length, 2, reason: 'moved to Recently deleted');
      expect(find.text(top), findsNothing);
      expect(t.getTopLeft(below).dy, lastY, reason: 'no jump when the collapsed row is finally removed');
      expect(find.text('Undo'), findsOneWidget);
    });
  });
}
