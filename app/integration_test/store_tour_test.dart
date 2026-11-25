// Play Store screenshots: the real app on an emulator with a small, realistic library, driven by
// `TEST=integration_test/store_tour_test.dart tool/capture_android.sh emulator-5554 build/store/raw light|dark`
// (same handshake as capture_test.dart). Recordings use the debug-only test tone; their peaks.bin is
// replaced by a speech-like envelope so the waveform looks like a voice (display only; the audio is untouched).
import 'dart:io';
import 'dart:math';

import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:earmark/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

late Services s;
late EngineClient engine;
late IntegrationTestWidgetsFlutterBinding binding;

Future<void> _until(WidgetTester t, bool Function() ok, String what) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > const Duration(seconds: 60)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await t.pump();
}

Future<void> _settle(WidgetTester t, [int ms = 700]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
}

/// Names the scene and waits until the host has taken the screenshot.
Future<void> _scene(WidgetTester t, String name) async {
  await _settle(t, 1200);
  final dir = Directory(s.library.root!).parent.path;
  File('$dir/capture_scene.txt').writeAsStringSync(name);
  final ack = File('$dir/capture_ack.txt');
  final sw = Stopwatch()..start();
  while (!(ack.existsSync() && ack.readAsStringSync().trim() == name)) {
    if (sw.elapsed > const Duration(seconds: 60)) fail('the host did not take $name');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await t.pump(); // keep drawing: a held touch from the host changes the screen while we wait
  }
}

/// Records for [stopAt] ms with marks at [marksAt]; returns the saved recording's id.
Future<String> _record(WidgetTester t, List<int> marksAt, int stopAt) async {
  await t.tap(find.bySemanticsLabel('Start recording'));
  await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
  for (final at in marksAt) {
    await _until(t, () => engine.snapshot.value.positionMs >= at, '$at ms');
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
  }
  await _until(t, () => engine.snapshot.value.positionMs >= stopAt, 'stop at $stopAt');
  await t.tap(find.bySemanticsLabel('Stop and save'));
  await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'saved');
  final id = engine.lastSaved.value!.id;
  await _until(t, () => s.library.byId(id) != null, 'in the library');
  return id;
}

/// A voice-like level envelope (one byte per 50 ms): phrases of syllables with short pauses.
void _speechPeaks(String id, int seed) {
  final r = s.library.byId(id)!;
  final n = (r.durationMs / 50).ceil();
  final rnd = Random(seed);
  final out = Uint8List(n);
  var i = 0;
  while (i < n) {
    final phrase = 20 + rnd.nextInt(60); // 1-4 s of speech
    final loud = 120 + rnd.nextInt(110);
    for (var k = 0; k < phrase && i < n; k++, i++) {
      final syllable = 0.55 + 0.45 * sin(k * (0.9 + rnd.nextDouble() * 0.5)).abs();
      out[i] = (loud * syllable * (0.75 + rnd.nextDouble() * 0.25)).round().clamp(8, 255);
    }
    final pause = 3 + rnd.nextInt(10);
    for (var k = 0; k < pause && i < n; k++, i++) {
      out[i] = 6 + rnd.nextInt(14);
    }
  }
  File(r.peaksPath).writeAsBytesSync(out);
}

void main() {
  // Device-sourced pointer events (the held Bookmark below) reach the app during the test.
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()..shouldPropagateDevicePointerEvents = true;

  testWidgets('store tour', (t) async {
    engine = EngineClient();
    await engine.useTestTone(true);
    s = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: s));
    await _settle(t);
    await s.library.setCalmMode(false);
    await s.library.setPro(true); // quick labels on screen (Pro)

    // A small library: the newest one is the meeting the slides follow.
    final idea = await _record(t, [3000], 7000);
    await s.library.rename(idea, 'Idea: onboarding flow');
    await s.library.renameMark(idea, s.library.byId(idea)!.userMarks[0].id, 'Launch checklist');
    final interview = await _record(t, [4000, 9000], 13000);
    await s.library.rename(interview, 'Interview with Sam');
    final im = s.library.byId(interview)!.userMarks;
    await s.library.renameMark(interview, im[0].id, 'Best quote');
    await s.library.renameMark(interview, im[1].id, 'Launch plans');
    final sync = await _record(t, [6000, 14000, 23000, 31000], 38000);
    await s.library.rename(sync, 'Weekly team sync');
    final marks = s.library.byId(sync)!.userMarks;
    for (final (i, name) in ['Budget question', 'Launch date', 'Action items'].indexed) {
      await s.library.renameMark(sync, marks[i].id, name);
    }
    for (final (i, id) in [idea, interview, sync].indexed) {
      _speechPeaks(id, 7 + i);
    }
    await _settle(t);
    await _scene(t, 'home');

    // Live: marks pile up, then a long press opens the quick labels (Pro).
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
    for (final at in [2500, 6000]) {
      await _until(t, () => engine.snapshot.value.positionMs >= at, 'live $at');
      await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    }
    await _until(t, () => engine.snapshot.value.positionMs >= 11000, 'live');
    await _scene(t, 'live');
    // A finger held on Bookmark, sent as a device event: a test gesture would draw the test
    // framework's touch crosshair into the picture.
    final c = t.getCenter(find.bySemanticsLabel('Bookmark this moment'));
    void finger(PointerEvent e) => binding.handlePointerEventForSource(e, source: TestBindingEventSource.device);
    finger(PointerDownEvent(pointer: 77, position: c));
    for (var i = 0; i < 12; i++) {
      await _settle(t, 100);
    }
    await _scene(t, 'labels');
    finger(PointerCancelEvent(pointer: 77, position: c));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'saved');
    await _settle(t);

    // Library, search, Playback, Clip.
    await t.tap(find.bySemanticsLabel('Library'));
    await _settle(t);
    await _scene(t, 'library');
    await t.enterText(find.byType(TextField), 'launch');
    await _settle(t);
    FocusManager.instance.primaryFocus?.unfocus(); // keyboard away
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await _settle(t, 2000);
    await _scene(t, 'search');
    await t.tap(find.bySemanticsLabel(RegExp('^Launch date at .*Weekly team sync')));
    await _settle(t, 1500);
    await _scene(t, 'playback');
    await t.tap(find.bySemanticsLabel('Share clip of Launch date'));
    await _settle(t, 1500);
    await _scene(t, 'clip');
    await t.tapAt(const Offset(40, 80));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('Back'));
    await _settle(t);
    await t.tap(find.bySemanticsLabel('Back to Record'));
    await _settle(t);

    await t.tap(find.bySemanticsLabel('Settings'));
    await _settle(t, 1200);
    await _scene(t, 'settings');
    await s.library.setPro(false);
    await _scene(t, 'done');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
