// Fault injection on a device, driven by tool/fault_android.sh (not part of the normal suite):
// 1. five quick Record/Stop cycles must not crash the engine or the service;
// 2. a recording with a mark, then a long wait during which the host kills the process with
//    kill -9; the host relaunches the app and checks what recovery kept.
// The engine records its debug-only test tone, never the microphone.
import 'dart:io';

import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:earmark/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> _until(WidgetTester t, bool Function() ok, String what) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > const Duration(seconds: 20)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await t.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('five quick Record/Stop cycles', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    final services = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: services));
    await t.pump();
    for (var i = 0; i < 5; i++) {
      await t.tap(find.bySemanticsLabel('Start recording'));
      await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording $i');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await t.tap(find.bySemanticsLabel('Stop and save'));
      await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'idle $i');
    }
    // The host reads this file (prints go to the PC, not to the device log).
    File('${Directory(services.library.root!).parent.path}/fault_cycles.txt').writeAsStringSync('done');
  });

  testWidgets('frame timing on the live Record screen (debug build: an upper bound)', (t) async {
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    final engine = EngineClient();
    await engine.useTestTone(true);
    final services = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: services));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await t.tap(find.bySemanticsLabel('Bookmark this moment'));
      }
    }, reportKey: 'live');
    final r = binding.reportData!['live'] as Map<String, dynamic>;
    String f(String k) => (r[k] as num?)?.toStringAsFixed(2) ?? '-';
    // ignore: avoid_print
    print('RESULT frames: ${r['frame_count']} frames; build avg ${f('average_frame_build_time_millis')} ms, '
        '99th ${f('99th_percentile_frame_build_time_millis')} ms, worst ${f('worst_frame_build_time_millis')} ms, '
        'missed build budget ${r['missed_frame_build_budget_count']}; raster avg ${f('average_frame_rasterizer_time_millis')} ms, '
        '99th ${f('99th_percentile_frame_rasterizer_time_millis')} ms, missed raster budget ${r['missed_frame_rasterizer_budget_count']}');
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.snapshot.value.state == SessionState.idle, 'idle');
  });

  testWidgets('record, then get killed by the host', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    final services = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: services));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.positionMs >= 3000, '3 s');
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await _until(t, () => engine.snapshot.value.positionMs >= 8000, '8 s');
    await engine.refresh();
    final s = engine.snapshot.value;
    File('${Directory(services.library.root!).parent.path}/fault_ready.txt')
        .writeAsStringSync('id=${s.recordingId} pos=${s.positionMs} at=${DateTime.now().millisecondsSinceEpoch}');
    await Future<void>.delayed(const Duration(seconds: 90)); // killed during this wait
  });
}
