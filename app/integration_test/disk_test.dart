// Low storage on an EMULATOR only (tool/disk_android.sh fills its /data; never run on a phone):
// the engine must stop by itself with stopReason "low_storage", finalize audio.m4a and leave no
// second copy behind. The engine records its debug-only test tone, never the microphone.
import 'dart:io';

import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:earmark/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('low storage stops and saves cleanly', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    final services = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: services));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Start recording'));
    final sw = Stopwatch()..start();
    while (engine.snapshot.value.positionMs < 5000) {
      if (sw.elapsed > const Duration(seconds: 30)) fail('did not start');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    File('${Directory(services.library.root!).parent.path}/disk_ready.txt').writeAsStringSync('${engine.snapshot.value.recordingId}');
    // The host now fills the disk; the engine checks free space every 15 s.
    while (engine.lastSaved.value == null) {
      if (sw.elapsed > const Duration(seconds: 240)) fail('the engine never stopped for low storage');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final r = engine.lastSaved.value!;
    final files = Directory(r.folder).listSync().map((e) => e.uri.pathSegments.last).toList();
    debugPrint('RESULT low storage: stopReason=${r.stopReason} duration=${r.durationMs} ms files=$files');
    expect(r.stopReason, 'low_storage');
    expect(files, contains('audio.m4a'));
    expect(files.where((f) => f.endsWith('.tmp')), isEmpty, reason: 'no second copy left behind');
    expect(files, isNot(contains('audio.aac.part')));
  });
}
