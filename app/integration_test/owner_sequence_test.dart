// The owner's acceptance sequence through the real UI and the real Android engine:
// record 10 s → Bookmark → Pause 5 s → Resume 10 s → Bookmark (near the end) → Stop.
// Expect marks at 10.0 s and 20.0 s (± 0.1 s); paused time excluded.
//
// "10 s" is measured on the recording's own clock, the way a user watches the timer: the test
// takes a fresh engine reading, then taps when the recording reaches 10.0 s. Between that
// reading and the tap, ~9 s of wall time must equal ~9 s of recorded frames, so this also
// proves the engine neither drops nor invents audio. (A test stopwatch started when the UI
// first shows "Recording" is not usable: an emulator's first live frame can stall ~1 s.)
//
// The engine records its clock-paced test tone (debug builds only): an emulator's virtual
// microphone runs 5-12 % fast, which would test the emulator, not Earmark. The real
// microphone's timing is a physical-phone check (docs/DEVICE-CHECKS.md).
//
// Run (Git Bash, from app/, emulator or phone connected; grants the permissions for you):
//   tool/integration_android.sh emulator-5554
import 'dart:io';

import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Real wall-clock wait. No pumping meanwhile: the app draws its own frames, and forced
/// pumps would load the emulator's UI thread and delay the tap being measured.
Future<void> _wait(WidgetTester t, Duration d) async {
  if (d > Duration.zero) await Future<void>.delayed(d);
  await t.pump();
}

Future<void> _until(WidgetTester t, bool Function() ok, String what) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > const Duration(seconds: 8)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await t.pump();
}

/// Waits until the recording's own clock reaches [targetMs], estimated from one fresh reading
/// (plus half its round trip), then returns the wall time spent since that reading.
Future<int> _waitForPosition(WidgetTester t, EngineClient e, int targetMs) async {
  final rtt = Stopwatch()..start();
  await e.refresh();
  final reading = e.snapshot.value.positionMs + rtt.elapsedMilliseconds ~/ 2;
  final since = Stopwatch()..start();
  await Future<void>.delayed(Duration(milliseconds: targetMs - reading));
  return since.elapsedMilliseconds;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner sequence: 10 s, mark, pause 5 s, resume 10 s, mark, stop', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    await t.pumpWidget(EarmarkApp(engine: engine));
    await t.pump();

    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
    await _wait(t, const Duration(milliseconds: 800)); // let the first live frames settle

    final span1 = await _waitForPosition(t, engine, 10000);
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await _until(t, () => engine.marks.value.length == 1, 'mark 1');

    await t.tap(find.bySemanticsLabel('Pause recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.paused, 'paused');
    await engine.refresh();
    final atPause = engine.snapshot.value.positionMs;
    expect(find.bySemanticsLabel('Paused'), findsOneWidget);

    await _wait(t, const Duration(seconds: 5));
    await engine.refresh();
    expect(engine.snapshot.value.positionMs, atPause, reason: 'paused time must not be counted');

    await t.tap(find.bySemanticsLabel('Resume recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording again');
    await _wait(t, const Duration(milliseconds: 800));
    final span2 = await _waitForPosition(t, engine, 20000);
    await t.tap(find.bySemanticsLabel('Bookmark this moment'));
    await _until(t, () => engine.marks.value.length == 2, 'mark 2');

    await _wait(t, const Duration(milliseconds: 300)); // a bookmark near the end
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.lastSaved.value != null, 'saved');
    await t.pump();

    final r = engine.lastSaved.value!;
    final m1 = r.marks[0].positionMs, m2 = r.marks[1].positionMs;
    // ignore: avoid_print
    print('RESULT mark1=$m1 ms, mark2=$m2 ms, paused at $atPause ms (held 5 s), '
        'duration=${r.durationMs} ms; wall spans checked: $span1 ms and $span2 ms');

    expect(r.marks, hasLength(2));
    expect((m1 - 10000).abs(), lessThanOrEqualTo(100), reason: 'mark 1 at 00:10');
    expect((m2 - 20000).abs(), lessThanOrEqualTo(100), reason: 'mark 2 at 00:20');
    expect(m2, lessThan(r.durationMs), reason: 'the end mark is inside the recording');
    expect(r.durationMs - m2, inInclusiveRange(250, 700), reason: 'stopped ~0.3 s after mark 2');
    expect(File('${r.folder}/audio.m4a').existsSync(), isTrue);
    expect(File('${r.folder}/audio.aac.part').existsSync(), isFalse);
    expect(File('${r.folder}/marks.jsonl').readAsLinesSync(), hasLength(2));
    expect(find.bySemanticsLabel(RegExp(r'^Saved recording, 00:20 · 2 marks$')), findsOneWidget);
  });

  testWidgets('five taps in one second make five marks', (t) async {
    final engine = EngineClient();
    await engine.useTestTone(true);
    await t.pumpWidget(EarmarkApp(engine: engine));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Start recording'));
    await _until(t, () => engine.snapshot.value.state == SessionState.recording, 'recording');
    await _wait(t, const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await t.tap(find.bySemanticsLabel('Bookmark this moment'));
      await _wait(t, const Duration(milliseconds: 180));
    }
    await _until(t, () => engine.marks.value.length == 5, 'five marks');
    await t.tap(find.bySemanticsLabel('Stop and save'));
    await _until(t, () => engine.lastSaved.value?.marks.length == 5, 'saved with five marks');
    final p = engine.lastSaved.value!.marks.map((m) => m.positionMs).toList();
    for (var i = 1; i < p.length; i++) {
      expect(p[i], greaterThan(p[i - 1]));
    }
  });
}
