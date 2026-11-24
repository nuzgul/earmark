// Property tests: thousands of random inputs against the clip maths, the library reader and the
// edit operations. Seeds are fixed so a failure reproduces; the seed is in the message.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:earmark/data/library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('clip window: always inside the recording, 20 s when it can be, around the mark', () {
    for (var seed = 0; seed < 20000; seed++) {
      final r = Random(seed);
      final dur = r.nextInt(4) == 0 ? r.nextInt(25000) : r.nextInt(3 * 3600 * 1000);
      final mark = r.nextInt(dur + 2001) - 1000;
      final w = clipWindow(mark, dur);
      final why = 'seed $seed: mark $mark, duration $dur → $w';
      expect(w.start, greaterThanOrEqualTo(0), reason: why);
      expect(w.end, lessThanOrEqualTo(dur), reason: why);
      expect(w.end - w.start, dur >= 20000 ? 20000 : dur, reason: why);
      if (dur >= 20000 && mark >= 0 && mark <= dur) {
        expect(mark, inInclusiveRange(w.start, w.end), reason: why);
      }
    }
  });

  test('library reader: random and damaged files never crash the load or produce a bad recording', () async {
    final tmp = Directory.systemTemp.createTempSync('earmark-prop');
    final root = Directory('${tmp.path}/recordings')..createSync();
    final r = Random(7);
    String junk() => String.fromCharCodes(List.generate(r.nextInt(120), (_) => r.nextInt(0x3000)));
    for (var i = 0; i < 400; i++) {
      final id = 'f$i';
      writeRecording(root.path, id, at: DateTime(2026, 1, 1).add(Duration(minutes: i)), durationMs: 1000 + r.nextInt(600000),
          marksMs: List.generate(r.nextInt(6), (_) => r.nextInt(700000)));
      final d = '${root.path}/$id';
      switch (r.nextInt(8)) {
        case 0:
          File('$d/meta.json').writeAsStringSync(junk());
        case 1:
          final m = File('$d/meta.json').readAsStringSync();
          File('$d/meta.json').writeAsStringSync(m.substring(0, r.nextInt(m.length)));
        case 2:
          File('$d/marks.jsonl').writeAsStringSync('${junk()}\n${junk()}');
        case 3:
          File('$d/library.json').writeAsStringSync(junk());
        case 4:
          File('$d/library.json').writeAsStringSync(jsonEncode({'labels': 5, 'deleted': 'x', 'added': [1, 'a', {}], 'title': 7}));
        case 5:
          File('$d/meta.json').writeAsStringSync(jsonEncode({'id': id, 'created_at': 'soon', 'duration_ms': -5}));
        case 6:
          File('$d/audio.m4a').deleteSync();
        default:
          break; // a good one
      }
    }
    final lib = LibraryStore(root.path);
    await lib.load();
    expect(lib.loaded, isTrue);
    expect(lib.recordings.length + lib.recentlyDeleted.length, greaterThan(100), reason: 'the good folders still load');
    for (final rec in [...lib.recordings, ...lib.recentlyDeleted]) {
      expect(rec.durationMs, greaterThanOrEqualTo(0), reason: rec.id);
      final pos = rec.marks.map((m) => m.posMs).toList();
      expect(pos, orderedEquals([...pos]..sort()), reason: '${rec.id}: marks sorted');
      if (rec.durationMs > 0) expect(pos.every((p) => p <= rec.durationMs), isTrue, reason: '${rec.id}: marks inside');
    }
    for (final q in ['', ' ', '04:', 'mark', '(', '[', r'\', '*', 'İ', 'ﬀ', '\u0000', junk()]) {
      lib.search(q); // never throws
    }
    tmp.deleteSync(recursive: true);
  });

  test('mark edits: any sequence of add / delete / undo / rename keeps numbers unique and never reused', () async {
    final tmp = Directory.systemTemp.createTempSync('earmark-prop');
    final root = Directory('${tmp.path}/recordings')..createSync();
    writeRecording(root.path, 'a', at: DateTime(2026, 1, 1), durationMs: 600000, marksMs: [10000, 20000, 30000]);
    final lib = LibraryStore(root.path);
    await lib.load();
    final r = Random(11);
    final everUsed = <int>{1, 2, 3};
    final deleted = <String>[];
    for (var step = 0; step < 150; step++) {
      final marks = lib.byId('a')!.userMarks;
      switch (r.nextInt(5)) {
        case 0 || 1:
          // Two adds at once, as a double tap would do.
          final added = await Future.wait([lib.addMark('a', r.nextInt(600000)), lib.addMark('a', r.nextInt(600000))]);
          for (final m in added) {
            expect(everUsed.contains(m.n), isFalse, reason: 'step $step: number ${m.n} reused');
            everUsed.add(m.n);
          }
        case 2:
          if (marks.isNotEmpty) {
            final m = marks[r.nextInt(marks.length)];
            await lib.deleteMark('a', m.id);
            deleted.add(m.id);
          }
        case 3:
          if (deleted.isNotEmpty) await lib.undoDeleteMark('a', deleted.removeLast());
        default:
          if (marks.isNotEmpty) await lib.renameMark('a', marks[r.nextInt(marks.length)].id, 'L$step');
      }
      final ns = lib.byId('a')!.userMarks.map((m) => m.n).toList();
      expect(ns.toSet().length, ns.length, reason: 'step $step: duplicate numbers $ns');
    }
    final again = LibraryStore(root.path);
    await again.load();
    expect(again.byId('a')!.userMarks.map((m) => m.id).toSet(), lib.byId('a')!.userMarks.map((m) => m.id).toSet(),
        reason: 'what is on disk is what the screen showed');
    tmp.deleteSync(recursive: true);
  });
}
