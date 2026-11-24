// "Make it expensive" and accessibility checks that a widget test can measure
// (docs/ui-premium/AUDIT-expensive-2026-11-24.md).
import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_client.dart';
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
}
