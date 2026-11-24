import 'dart:async';
import 'dart:io';

import 'package:earmark/app/design/theme.dart';
import 'package:earmark/app/services.dart';
import 'package:earmark/data/library.dart';
import 'package:earmark/engine/engine_api.g.dart';
import 'package:earmark/engine/engine_client.dart';
import 'package:earmark/features/pro/pro.dart';
import 'package:earmark/features/record/record_screen.dart';
import 'package:earmark/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class FakeStore implements Store {
  FakeStore({this.forSale});

  final String? forSale;
  final _events = StreamController<StoreEvent>.broadcast();
  bool refuseBuy = false;
  @override
  Future<void> Function()? onOwned;
  int buys = 0, restores = 0;

  void send(StoreEvent e) => _events.add(e);

  @override
  Future<String?> price() async => forSale;
  @override
  Future<void> buy() async {
    buys++;
    if (refuseBuy) throw StateError('purchase not started');
  }
  @override
  Future<void> restore() async => restores++;
  @override
  Stream<StoreEvent> get events => _events.stream;
}

/// A recordings folder inside a temp dir, so settings.json (next to it) stays out of the system temp.
String _root() {
  final root = '${Directory.systemTemp.createTempSync('earmark4').path}/recordings';
  Directory(root).createSync();
  return root;
}

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: child))),
      ),
    );

Widget _record(Services s) => MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: RecordScreen(services: s)),
    );

/// Goldens are compared on Windows only, where they are rendered (fonts rasterise differently on
/// Linux CI); the functional checks around them run everywhere.
Future<void> _golden(Finder f, String file) async {
  if (Platform.isWindows) await expectLater(f, matchesGoldenFile(file));
}

/// A 390 × 844 phone, as the other goldens use.
void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(loadTestFonts);

  group('settings', () {
    test('pre-roll seconds, calm screen, quick labels and Pro are kept', () async {
      final root = _root();
      final a = LibraryStore(root);
      await a.load();
      expect((a.preRollMs, a.calmMode, a.pro), (3000, true, false));
      expect(a.quickLabels, LibraryStore.defaultQuickLabels);
      await a.setPreRollSeconds(10);
      await a.setCalmMode(false);
      await a.setQuickLabels(['Hook', '', 'Quote', '']);
      await a.setPro(true);
      final b = LibraryStore(root);
      await b.load();
      expect((b.preRollMs, b.calmMode, b.pro), (10000, false, true));
      expect(b.quickLabels, ['Hook', '', 'Quote', '']);
      await b.setPreRoll(false);
      expect(b.preRollMs, 0);
    });

    test('a quick label given while recording shows once the recording is saved', () async {
      final root = _root();
      final lib = LibraryStore(root);
      await lib.load();
      writeRecording(root, 'r1', at: DateTime(2026, 11, 24, 9), marksMs: [4000, 9000]);
      File('$root/r1/audio.m4a').deleteSync(); // still recording
      await lib.labelLiveMark('r1', 'r1-m2', 'Idea');
      expect(lib.byId('r1'), isNull);
      File('$root/r1/audio.m4a').writeAsBytesSync([0]); // saved
      lib.upsert('$root/r1');
      expect(lib.byId('r1')!.userMarks.map((m) => m.name), ['Mark 1', 'Idea']);
    });
  });

  group('Pro sheet', () {
    testWidgets('without a store, Buy is off and says why; the app stays complete', (t) async {
      _phone(t);
      final lib = LibraryStore(null);
      await t.pumpWidget(_host(ProSheet(pro: Pro(store: NoStore(), library: lib))));
      await t.pump();
      expect(find.textContaining("isn't on sale yet"), findsOneWidget);
      expect(t.getSemantics(find.bySemanticsLabel('Buy Pro')), isSemantics(label: 'Buy Pro', isButton: true, isEnabled: false));
      await _golden(find.byType(ProSheet), 'goldens/pro_sheet_unavailable_dark.png');
    });

    testWidgets('buy: the store confirms, Pro turns on and is remembered', (t) async {
      _phone(t);
      final lib = LibraryStore(_root());
      final store = FakeStore(forSale: '€5.99');
      final pro = Pro(store: store, library: lib);
      await t.pumpWidget(_host(ProSheet(pro: pro)));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Buy Pro · €5.99'));
      await t.pump();
      expect(store.buys, 1);
      expect(find.bySemanticsLabel('Waiting for the store…'), findsOneWidget);
      await t.runAsync(() async {
        store.send(StoreEvent.owned);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      expect(find.textContaining('Pro is on'), findsOneWidget);
      expect(lib.pro, isTrue); // kept across launches: see the settings test
    });

    testWidgets('store refuses to open the purchase: the sheet is not stuck and points to Restore', (t) async {
      _phone(t);
      final store = FakeStore(forSale: '€5.99')..refuseBuy = true;
      final pro = Pro(store: store, library: LibraryStore(null));
      await t.pumpWidget(_host(ProSheet(pro: pro)));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Buy Pro · €5.99'));
      await t.pump();
      expect(pro.busy, isFalse);
      expect(find.textContaining('tap Restore purchase'), findsOneWidget);
    });

    testWidgets('restore tapped twice: one "nothing found" message, and an owned answer cancels it', (t) async {
      _phone(t);
      final store = FakeStore(forSale: '€5.99');
      final pro = Pro(store: store, library: LibraryStore(null));
      await t.pumpWidget(_host(ProSheet(pro: pro)));
      await t.pump();
      unawaited(pro.restore());
      await t.pump(const Duration(seconds: 5));
      unawaited(pro.restore());
      await t.pump(const Duration(seconds: 4)); // 9 s after the first, 4 s after the second
      expect(pro.message, isNull, reason: 'the first timer was replaced');
      store.send(StoreEvent.owned);
      await t.pump(const Duration(seconds: 10));
      expect(pro.owned, isTrue);
      expect(find.text('No Pro purchase found for this store account.'), findsNothing);
    });

    testWidgets('restore with nothing to restore says so', (t) async {
      _phone(t);
      final store = FakeStore(forSale: '€5.99');
      await t.pumpWidget(_host(ProSheet(pro: Pro(store: store, library: LibraryStore(null)))));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Restore purchase'));
      await t.pump(const Duration(seconds: 9));
      expect(store.restores, 1);
      expect(find.text('No Pro purchase found for this store account.'), findsOneWidget);
    });
  });

  testWidgets('Settings: pre-roll choice, calm switch, Pro-only quick labels', (t) async {
      _phone(t);
    final lib = LibraryStore(_root());
    final s = Services(engine: EngineClient(api: FakeHostApi()), library: lib, newPlayer: FakePlayer.new);
    await t.pumpWidget(_host(SettingsSheet(services: s)));
    await _golden(find.byType(SettingsSheet), 'goldens/settings_dark.png');

    await t.tap(find.bySemanticsLabel('5 seconds'));
    await t.pump();
    expect((lib.preRoll, lib.preRollSeconds), (true, 5));
    await t.tap(find.bySemanticsLabel('Off'));
    await t.pump();
    expect(lib.preRoll, isFalse);
    await t.tap(find.byType(Switch));
    await t.pump();
    expect(lib.calmMode, isFalse);

    await t.tap(find.bySemanticsLabel('Quick labels, Pro'));
    await t.pumpAndSettle();
    expect(find.text('One payment, yours for good. No subscription, no account.'), findsOneWidget);
  });

  group('Record screen', () {
    testWidgets('calm screen: dims after 20 s; the first touch only wakes, Bookmark still marks', (t) async {
      _phone(t);
      final api = FakeHostApi();
      final engine = EngineClient(api: api);
      await t.pumpWidget(_record(Services(engine: engine, library: LibraryStore(null), newPlayer: FakePlayer.new)));
      await t.tap(find.bySemanticsLabel('Start recording'));
      await t.pump();
      Future<void> heartbeat(Duration d) async {
        for (var left = d; left > Duration.zero; left -= const Duration(milliseconds: 250)) {
          engine.onSnapshot(api.now); // keeps the 1.5 s watchdog quiet
          await t.pump(const Duration(milliseconds: 250));
        }
      }

      await heartbeat(const Duration(seconds: 21));
      final pill = find.ancestor(of: find.bySemanticsLabel('Recording'), matching: find.byType(AnimatedOpacity)).first;
      expect(t.widget<AnimatedOpacity>(pill).opacity, 0.35);
      await _golden(find.byType(RecordScreen), 'goldens/record_calm_dark.png');

      await t.tap(find.bySemanticsLabel('Stop and save'));
      await heartbeat(const Duration(milliseconds: 500));
      expect(api.state, SessionState.recording, reason: 'the first touch only wakes the screen');
      expect(t.widget<AnimatedOpacity>(pill).opacity, 1);

      await heartbeat(const Duration(seconds: 21));
      await t.tap(find.bySemanticsLabel('Bookmark this moment'));
      await t.pump();
      expect(api.marks, hasLength(1), reason: 'Bookmark marks even while calm (and wakes the screen)');

      await t.tap(find.bySemanticsLabel('Stop and save'));
      await t.pumpAndSettle();
      expect(api.state, SessionState.idle);
      engine.dispose();
    });

    testWidgets('quick labels (Pro): hold Bookmark, slide to a label, let go', (t) async {
      _phone(t);
      final root = _root();
      Directory('$root/rec-1').createSync(); // the engine's folder for the recording in progress
      final lib = LibraryStore(root);
      await t.runAsync(() => lib.setPro(true));
      final api = FakeHostApi();
      final engine = EngineClient(api: api);
      await t.pumpWidget(_record(Services(engine: engine, library: lib, newPlayer: FakePlayer.new)));
      await t.tap(find.bySemanticsLabel('Start recording'));
      await t.pump();
      api.ms = 12000;
      engine.onSnapshot(api.now);
      await t.pump();

      final g = await t.startGesture(t.getCenter(find.bySemanticsLabel('Bookmark this moment')));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Quote'), findsOneWidget);
      await _golden(find.byType(RecordScreen), 'goldens/record_quick_labels_dark.png');
      await g.moveTo(t.getCenter(find.text('Quote')));
      await t.pump();
      await g.up();
      final labels = File('$root/rec-1/library.json');
      for (var i = 0; i < 200 && !labels.existsSync(); i++) {
        // The label file is real I/O: let it finish, then run its continuation (up to 6 s on a busy machine).
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
      }

      expect(api.marks, hasLength(1), reason: 'one mark, made on touch-down');
      expect(find.bySemanticsLabel('Quote, Mark 1 at 12 seconds'), findsOneWidget);
      expect(File('$root/rec-1/library.json').readAsStringSync(), contains('"m1":"Quote"'));

      await t.tap(find.bySemanticsLabel('Stop and save'));
      await t.pumpAndSettle();
      engine.dispose();
    });
  });
}
