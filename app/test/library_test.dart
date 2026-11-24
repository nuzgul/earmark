import 'dart:io';

import 'package:earmark/data/library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Directory tmp;
  final now = DateTime(2026, 11, 24, 15, 0);

  setUp(() => tmp = Directory.systemTemp.createTempSync('earmark'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('clip window', () {
    test('middle: 14 s before, 6 s after', () => expect(clipWindow(60000, 120000), (start: 46000, end: 66000)));
    test('near the start shifts right', () => expect(clipWindow(5000, 120000), (start: 0, end: 20000)));
    test('near the end shifts left', () => expect(clipWindow(118000, 120000), (start: 100000, end: 120000)));
    test('short recording is used whole', () {
      expect(clipWindow(500, 6000), (start: 0, end: 6000));
      expect(clipWindow(5500, 6000), (start: 0, end: 6000));
    });
  });

  test('titles, groups and clip names', () {
    expect(defaultTitle(DateTime(2026, 11, 24, 9, 5)), 'Tue 24 Nov, 09:05');
    expect(dayGroup(DateTime(2026, 11, 24, 1), now), 'Today');
    expect(dayGroup(DateTime(2026, 11, 23, 23), now), 'Yesterday');
    expect(dayGroup(DateTime(2026, 11, 19), now), 'This week');
    expect(dayGroup(DateTime(2026, 10, 1), now), 'Older');
    final r = Recording(id: 'a', folder: '/x', createdAt: now, durationMs: 1, marks: const [], customTitle: 'Pitch rehearsal');
    expect(clipFileName(r, const Mark(id: 'm', posMs: 0, n: 3), 258000, 278000),
        'Pitch rehearsal — Mark 3 (04-18 to 04-38).m4a');
  });

  test('reads engine folders, skips torn lines and unfinished recordings', () async {
    writeRecording(tmp.path, 'a', at: now, marksMs: [10000, 20000], callAtMs: 15000);
    Directory('${tmp.path}/live').createSync(); // in progress: no audio.m4a yet
    final s = LibraryStore(tmp.path, now: () => now);
    await s.load();
    expect(s.recordings, hasLength(1));
    final r = s.recordings.single;
    expect(r.userMarks.map((m) => (m.posMs, m.name)), [(10000, 'Mark 1'), (20000, 'Mark 2')]);
    expect(r.marks.where((m) => m.system).single.name, 'Paused: call');
  });

  test('mark numbers survive deletes; added marks take the next number; undo restores', () async {
    writeRecording(tmp.path, 'a', at: now, marksMs: [1000, 2000, 3000]);
    final s = LibraryStore(tmp.path, now: () => now);
    await s.load();
    await s.deleteMark('a', 'a-m3');
    expect(s.byId('a')!.userMarks.map((m) => m.name), ['Mark 1', 'Mark 2']);
    final added = await s.addMark('a', 2500);
    expect(added.name, 'Mark 4');
    await s.renameMark('a', 'a-m1', 'Chorus');
    await s.undoDeleteMark('a', 'a-m3');

    final again = LibraryStore(tmp.path, now: () => now); // edits are on disk
    await again.load();
    expect(again.byId('a')!.userMarks.map((m) => m.name), ['Chorus', 'Mark 2', 'Mark 4', 'Mark 3']);
  });

  test('rename, recently deleted, restore, purge after 30 days, delete forever', () async {
    writeRecording(tmp.path, 'a', at: now);
    writeRecording(tmp.path, 'b', at: now.subtract(const Duration(hours: 1)));
    var clock = now;
    final s = LibraryStore(tmp.path, now: () => clock);
    await s.load();
    await s.rename('a', '  Pitch rehearsal ');
    expect(s.byId('a')!.title, 'Pitch rehearsal');
    await s.delete('a');
    expect(s.recordings.map((r) => r.id), ['b']);
    expect(s.recentlyDeleted.map((r) => r.id), ['a']);
    await s.restore('a');
    expect(s.recordings, hasLength(2));

    await s.delete('a');
    clock = now.add(const Duration(days: 31));
    await s.load();
    expect(s.byId('a'), isNull);
    expect(Directory('${tmp.path}/a').existsSync(), isFalse);

    await s.deleteForever('b');
    expect(Directory('${tmp.path}/b').existsSync(), isFalse);
  });

  test('search finds marks by label, number and time, then recordings by title', () async {
    writeRecording(tmp.path, 'a', at: now, marksMs: [272000, 30000]);
    writeRecording(tmp.path, 'b', at: now.subtract(const Duration(days: 2)));
    final s = LibraryStore(tmp.path, now: () => now);
    await s.load();
    await s.rename('b', 'Mark the date');
    await s.renameMark('a', 'a-m2', 'Second verse');

    expect(s.search('04:32').marks.single.mark.name, 'Mark 1');
    expect(s.search('verse').marks.single.mark.posMs, 30000);
    final hits = s.search('mark');
    expect(hits.marks.map((h) => h.mark.name), ['Mark 1']);
    expect(hits.recordings.map((r) => r.id), ['b']);
    expect(s.search('  ').isEmpty, isTrue);
  });

  test('pre-roll setting persists', () async {
    final root = Directory('${tmp.path}/recordings')..createSync();
    final s = LibraryStore(root.path);
    await s.load();
    expect(s.preRoll, isTrue);
    await s.setPreRoll(false);
    final again = LibraryStore(root.path);
    await again.load();
    expect(again.preRoll, isFalse);
  });
}
