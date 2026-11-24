// Phase 2 acceptance on a real engine: replay a mark (with pre-roll) through the UI, then prove a
// clip's duration and content and that the source recording is untouched.
// The debug-only test tone's pitch encodes the second of audio: 300 Hz + 20 Hz × second.
//
// Run (Git Bash, from app/):  tool/integration_android.sh emulator-5554
import 'dart:io';

import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/playback/player.dart';
import 'package:earmark/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> _until(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(seconds: 40)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await t.pump();
}

/// Settles route and sheet animations in real time (pumpAndSettle would never settle while
/// the player's position keeps changing).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await t.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('replay a mark with pre-roll; lossless clip has the right length and content', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    final services = Services(engine: engine, library: LibraryStore(await engine.recordingsRoot()), newPlayer: JustAudioPlayer.new);
    await t.pumpWidget(EarmarkApp(services: services));
    await t.pump();

    debugPrint('STEP start');
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.positionMs >= 20000, '20 s recorded');
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await _until(t, () => engine.snapshot.value.positionMs >= 25000, '25 s recorded');
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.lastSaved.value != null && services.library.byId(engine.lastSaved.value!.id) != null, 'in library');

    final r = services.library.byId(engine.lastSaved.value!.id)!;
    final mark = r.userMarks.single;
    final source = File(r.audioPath).readAsBytesSync();
    debugPrint('RESULT recording ${r.durationMs} ms, mark at ${mark.posMs} ms');

    // Open it from the Saved strip, then jump from the flag: 3 s of pre-roll before the mark.
    debugPrint('STEP open playback');
    await t.tap(find.bySemanticsLabel(RegExp(r'^Saved recording, ')));
    await _settle(t);
    // Bracketed, so a slow host cannot fake a pass or a failure: the playhead must sit between
    // the pre-roll point and the pre-roll point plus the time that really passed.
    final sw = Stopwatch()..start();
    debugPrint('STEP jump');
    await t.tap(find.bySemanticsLabel(RegExp('^Mark 1 at .*, jump\$')));
    await _until(t, () => find.bySemanticsLabel(RegExp(r'^Pause$')).evaluate().isNotEmpty, 'playing');
    await t.tap(find.bySemanticsLabel(RegExp(r'^Pause$')));
    final elapsed = sw.elapsedMilliseconds;
    await _settle(t);
    final head = (find.byKey(const ValueKey('playhead')).evaluate().single.widget as Text).data!;
    final headMs = (int.parse(head.substring(0, 2)) * 60 + int.parse(head.substring(3))) * 1000;
    final from = mark.posMs - 3000;
    debugPrint('RESULT jump: playhead $head after $elapsed ms (pre-roll point ${clock(from)})');
    expect(headMs, inInclusiveRange(from ~/ 1000 * 1000, from + elapsed + 300), reason: 'jump lands 3 s before the mark');

    // The Clip sheet proposes 14 s before + 6 s after, kept inside the recording.
    debugPrint('STEP clip sheet');
    await t.tap(find.bySemanticsLabel('Share clip of Mark 1'));
    await _settle(t);
    final w = clipWindow(mark.posMs, r.durationMs);
    expect(find.text('${clock(w.start)} → ${clock(w.end)} · ${((w.end - w.start) / 1000).toStringAsFixed(1)} s'), findsOneWidget);

    // Export exactly what Share would export (the system share sheet itself is outside the app).
    debugPrint('STEP export');
    final clipPath = await engine.exportClip(r.folder, w.start, w.end, clipFileName(r, mark, w.start, w.end));
    debugPrint('STEP probe');
    final clip = await engine.probeAudio(clipPath);
    final whole = await engine.probeAudio(r.audioPath);
    final expectedHz = 300 + 20 * ((w.start + 200) ~/ 1000);
    debugPrint('RESULT clip ${w.start}-${w.end} ms -> ${clip.durationMs} ms, start pitch ${clip.startHz.toStringAsFixed(1)} Hz '
        '(expected $expectedHz); source start pitch ${whole.startHz.toStringAsFixed(1)} Hz');

    expect((clip.durationMs - (w.end - w.start)).abs(), lessThanOrEqualTo(100), reason: 'clip length');
    expect((clip.startHz - expectedHz).abs(), lessThanOrEqualTo(8), reason: 'clip starts at the right second');
    expect((whole.startHz - 300).abs(), lessThanOrEqualTo(8), reason: 'probe sanity: the recording starts at 300 Hz');
    expect(listEquals(File(r.audioPath).readAsBytesSync(), source), isTrue, reason: 'source recording unchanged');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

String clock(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
