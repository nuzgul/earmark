// Screens and motion for the "make it expensive" before/after record, driven by
// tool/capture_android.sh (emulator). Builds a realistic library with the debug-only test tone,
// then visits each screen. For a still, it names the scene in files/capture_scene.txt and holds;
// for a motion clip ("clip_*"), the host starts a screen recording and the action follows 1.2 s later.
import 'dart:io';

import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:earmark/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

late Services s;
late EngineClient engine;

Future<void> _until(WidgetTester t, bool Function() ok, String what) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > const Duration(seconds: 40)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await t.pump();
}

/// Real-time settle (pumpAndSettle never settles while the engine heartbeat runs).
Future<void> _settle(WidgetTester t, [int ms = 700]) async {
  for (var i = 0; i < ms ~/ 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await t.pump();
  }
}

Future<void> _scene(WidgetTester t, String name, {int holdMs = 2500}) async {
  File('${Directory(s.library.root!).parent.path}/capture_scene.txt').writeAsStringSync(name);
  await _settle(t, holdMs);
}

/// A motion clip: the host starts recording when the scene appears; the action follows.
Future<void> _clip(WidgetTester t, String name, Future<void> Function() action) async {
  File('${Directory(s.library.root!).parent.path}/capture_scene.txt').writeAsStringSync(name);
  await _settle(t, 1200);
  await action();
  await _settle(t, 2800);
}

Future<void> _record(WidgetTester t, List<int> marksAt, int stopAt) async {
  await t.tap(find.bySemanticsLabel('Start recording'));
  await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
  for (final at in marksAt) {
    await _until(t, () => engine.snapshot.value.positionMs >= at, '$at ms');
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
  }
  await _until(t, () => engine.snapshot.value.positionMs >= stopAt, 'stop at $stopAt');
  await t.tap(find.bySemanticsLabel('Stop and save'));
  await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'saved');
  await _until(t, () => s.library.byId(engine.lastSaved.value!.id) != null, 'in the library');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the main screens and motions', (t) async {
    engine = EngineClient();
    await engine.useTestTone(true);
    s = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: s));
    await _settle(t);

    // A small, realistic library.
    await _record(t, [3000], 6000);
    await _record(t, [3000, 6000, 9000], 12000);
    final main = engine.lastSaved.value!.id;
    await s.library.rename(main, 'Pitch rehearsal');
    await s.library.renameMark(main, s.library.byId(main)!.userMarks[1].id, 'Budget question');
    await _settle(t);
    await _scene(t, 'record_idle');

    // Live recording: the press on Bookmark, then the live screen with two marks.
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.positionMs >= 3000, 'live');
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await _clip(t, 'clip_bookmark_press', () async {
      final g = await t.startGesture(t.getCenter(find.bySemanticsLabel('Bookmark this moment')));
      await _settle(t, 350);
      await g.up();
    });
    await _scene(t, 'record_live');
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'saved');
    await _settle(t);

    // Library, Playback, Clip sheet.
    await t.tap(find.bySemanticsLabel('Library'));
    await _settle(t);
    await _scene(t, 'library');
    await _clip(t, 'clip_open_playback', () async {
      await t.tap(find.bySemanticsLabel(RegExp('^Pitch rehearsal, ')));
    });
    await _scene(t, 'playback');
    await _clip(t, 'clip_sheet_open_close', () async {
      await t.tap(find.bySemanticsLabel('Share clip of Budget question'));
      await _settle(t, 1500);
      await t.tapAt(const Offset(40, 80)); // the dimmed page above the sheet closes it
    });
    await t.tap(find.bySemanticsLabel('Share clip of Budget question'));
    await _settle(t);
    await _scene(t, 'clip_sheet');
    await t.tapAt(const Offset(40, 80));
    await _settle(t);
    await _clip(t, 'clip_delete_mark', () async {
      await t.tap(find.bySemanticsLabel('More for Mark 3'));
      await _settle(t, 700);
      await t.tap(find.bySemanticsLabel('Delete mark'));
    });
    await _clip(t, 'clip_back', () async {
      await t.tap(find.bySemanticsLabel('Back'));
    });
    await t.tap(find.bySemanticsLabel('Back to Record'));
    await _settle(t);

    // Settings and Pro.
    await _clip(t, 'clip_settings_open', () async {
      await t.tap(find.bySemanticsLabel('Settings'));
    });
    await _scene(t, 'settings');
    await t.tap(find.bySemanticsLabel(RegExp('^Earmark Pro')));
    await _settle(t, 1200);
    await _scene(t, 'pro_sheet');
    File('${Directory(s.library.root!).parent.path}/capture_scene.txt').writeAsStringSync('done');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
