import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/format.dart';

/// A point in a recording. User marks are numbered in the order they were made and keep their
/// number when others are deleted ("Mark 3" stays "Mark 3"). System marks note an interruption.
@immutable
class Mark {
  const Mark({required this.id, required this.posMs, required this.n, this.label, this.system = false, this.note});

  final String id;
  final int posMs;
  final int n;
  final String? label;
  final bool system;
  final String? note;

  String get name => label ?? (system ? 'Paused: ${note ?? 'interruption'}' : 'Mark $n');
}

@immutable
class Recording {
  const Recording({
    required this.id,
    required this.folder,
    required this.createdAt,
    required this.durationMs,
    required this.marks,
    this.customTitle,
    this.recovered = false,
    this.deletedAt,
    this.nextN = 1,
  });

  final String id;
  final String folder;
  final DateTime createdAt;
  final int durationMs;

  /// Sorted by position; deleted marks are not included.
  final List<Mark> marks;
  final String? customTitle;
  final bool recovered;
  final DateTime? deletedAt;

  /// Number for the next added mark; deleted numbers are not reused.
  final int nextN;

  String get title => customTitle ?? defaultTitle(createdAt);
  String get audioPath => '$folder/audio.m4a';
  String get peaksPath => '$folder/peaks.bin';
  List<Mark> get userMarks => marks.where((m) => !m.system).toList();
}

String _two(int v) => v.toString().padLeft(2, '0');
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Mon 24 Nov, 14:05"
String defaultTitle(DateTime t) => '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, ${hourMinute(t)}';

String hourMinute(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "24 Nov 2026"
String longDate(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';

/// Library groups, newest first.
String dayGroup(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return 'This week';
  return 'Older';
}

/// Clip around a mark: 14 s before + 6 s after, shifted to stay inside the recording;
/// a recording shorter than the window is used whole.
({int start, int end}) clipWindow(int markMs, int durationMs, {int before = 14000, int after = 6000}) {
  if (durationMs <= before + after) return (start: 0, end: durationMs);
  var start = markMs - before, end = markMs + after;
  if (start < 0) {
    end -= start;
    start = 0;
  }
  if (end > durationMs) {
    start -= end - durationMs;
    end = durationMs;
  }
  return (start: start, end: end);
}

/// "Pitch rehearsal — Mark 3 (04-18 to 04-38).m4a"
String clipFileName(Recording r, Mark m, int startMs, int endMs) {
  String t(int ms) => clock(ms).replaceAll(':', '-');
  return '${r.title} — ${m.name} (${t(startMs)} to ${t(endMs)}).m4a';
}

class SearchResults {
  const SearchResults(this.marks, this.recordings);

  final List<({Recording recording, Mark mark})> marks;
  final List<Recording> recordings;

  bool get isEmpty => marks.isEmpty && recordings.isEmpty;
}

/// The library is the recordings folder itself. The engine's files stay as written
/// (meta.json, marks.jsonl); the user's edits live next to them in library.json.
/// ponytail: whole library in memory, in-memory search; fine for thousands of recordings.
/// Move to SQLite + FTS only if a real library makes load or search slow.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this.root, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Null when this platform has no engine yet (iOS before Phase 3): empty library.
  final String? root;
  final DateTime Function() _now;

  /// The clock the screens use for "Today" and the 30-day countdown (fixed in tests).
  DateTime now() => _now();

  static const keepDeleted = Duration(days: 30);

  List<Recording> _all = const [];
  bool loaded = false;
  bool preRoll = true;

  List<Recording> get recordings => _all.where((r) => r.deletedAt == null).toList();
  List<Recording> get recentlyDeleted => _all.where((r) => r.deletedAt != null).toList();
  Recording? byId(String id) => _all.where((r) => r.id == id).firstOrNull;

  Future<void> load() async {
    final dir = root == null ? null : Directory(root!);
    final found = <Recording>[];
    if (dir != null && dir.existsSync()) {
      for (final d in dir.listSync().whereType<Directory>()) {
        final r = _read(d.path);
        if (r == null) continue;
        if (r.deletedAt != null && _now().difference(r.deletedAt!) > keepDeleted) {
          d.deleteSync(recursive: true); // the 30 days in Recently deleted are over
          continue;
        }
        found.add(r);
      }
      preRoll = _settings()['pre_roll'] as bool? ?? true;
    }
    found.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _all = found;
    loaded = true;
    notifyListeners();
  }

  /// After the engine saves or recovers a recording.
  void upsert(String folder) {
    final r = _read(folder);
    if (r == null) return;
    _all = [r, ..._all.where((e) => e.id != r.id)]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> rename(String id, String title) =>
      _edit(id, (e) => e['title'] = title.trim().isEmpty ? null : title.trim());

  Future<void> delete(String id) => _edit(id, (e) => e['deleted_at'] = _now().millisecondsSinceEpoch);

  Future<void> restore(String id) => _edit(id, (e) => e['deleted_at'] = null);

  /// Permanent: removes the audio and marks. The UI confirms first.
  Future<void> deleteForever(String id) async {
    final r = byId(id);
    if (r == null) return;
    final dir = Directory(r.folder);
    if (dir.existsSync()) await dir.delete(recursive: true);
    _all = _all.where((e) => e.id != id).toList();
    notifyListeners();
  }

  Future<Mark> addMark(String id, int posMs) async {
    final r = byId(id)!;
    final n = r.nextN;
    final markId = 'u${_now().microsecondsSinceEpoch}';
    await _edit(id, (e) => (e['added'] as List).add({'id': markId, 'pos_ms': posMs.clamp(0, r.durationMs), 'n': n}));
    return byId(id)!.marks.firstWhere((m) => m.id == markId);
  }

  Future<void> renameMark(String id, String markId, String label) => _edit(id, (e) {
        final t = label.trim();
        if (t.isEmpty) {
          (e['labels'] as Map).remove(markId);
        } else {
          (e['labels'] as Map)[markId] = t;
        }
      });

  Future<void> deleteMark(String id, String markId) => _edit(id, (e) => (e['deleted'] as List).add(markId));

  Future<void> undoDeleteMark(String id, String markId) => _edit(id, (e) => (e['deleted'] as List).remove(markId));

  Future<void> setPreRoll(bool on) async {
    preRoll = on;
    notifyListeners();
    if (root != null) await _settingsFile().writeAsString(jsonEncode({..._settings(), 'pre_roll': on}));
  }

  /// Marks first (label, "Mark N" or time such as "04:32"), then recordings by title.
  SearchResults search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const SearchResults([], []);
    final marks = <({Recording recording, Mark mark})>[];
    for (final r in recordings) {
      for (final m in r.userMarks) {
        if (m.name.toLowerCase().contains(q) || clock(m.posMs).contains(q)) marks.add((recording: r, mark: m));
      }
    }
    return SearchResults(marks, recordings.where((r) => r.title.toLowerCase().contains(q)).toList());
  }

  // ------------------------------------------------------------------ files

  File _settingsFile() => File('${Directory(root!).parent.path}/settings.json');

  Map<String, dynamic> _settings() {
    try {
      return jsonDecode(_settingsFile().readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _edits(String folder) {
    Map<String, dynamic> e;
    try {
      e = jsonDecode(File('$folder/library.json').readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      e = {};
    }
    e['labels'] ??= <String, dynamic>{};
    e['deleted'] ??= <dynamic>[];
    e['added'] ??= <dynamic>[];
    return e;
  }

  Future<void> _edit(String id, void Function(Map<String, dynamic>) change) async {
    final r = byId(id);
    if (r == null) return;
    final e = _edits(r.folder);
    change(e);
    final tmp = File('${r.folder}/library.json.tmp');
    await tmp.writeAsString(jsonEncode(e), flush: true);
    await tmp.rename('${r.folder}/library.json'); // atomic: a crash never leaves half a file
    upsert(r.folder);
  }

  /// Null for folders that are not a finished recording (in progress, or audio missing).
  Recording? _read(String folder) {
    try {
      if (!File('$folder/audio.m4a').existsSync()) return null;
      final meta = jsonDecode(File('$folder/meta.json').readAsStringSync()) as Map<String, dynamic>;
      final e = _edits(folder);
      final deleted = (e['deleted'] as List).toSet();
      final labels = e['labels'] as Map;
      final marks = <Mark>[];
      var n = 0;
      final journal = File('$folder/marks.jsonl');
      for (final line in journal.existsSync() ? journal.readAsLinesSync() : const <String>[]) {
        final Map<String, dynamic> j;
        try {
          j = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue; // a line cut off by a crash
        }
        final system = j['kind'] == 'system';
        if (!system) n++;
        final id = j['id'] as String;
        if (deleted.contains(id)) continue;
        marks.add(Mark(
          id: id,
          posMs: (j['pos_frames'] as int) * 1000 ~/ (j['sample_rate'] as int),
          n: system ? 0 : n,
          label: labels[id] as String?,
          system: system,
          note: j['note'] as String?,
        ));
      }
      for (final a in (e['added'] as List).cast<Map<String, dynamic>>()) {
        final id = a['id'] as String;
        if ((a['n'] as int) > n) n = a['n'] as int;
        if (deleted.contains(id)) continue;
        marks.add(Mark(id: id, posMs: a['pos_ms'] as int, n: a['n'] as int, label: labels[id] as String?));
      }
      marks.sort((a, b) => a.posMs.compareTo(b.posMs));
      return Recording(
        id: meta['id'] as String,
        folder: folder,
        createdAt: DateTime.fromMillisecondsSinceEpoch(meta['created_at'] as int),
        durationMs: meta['duration_ms'] as int,
        marks: marks,
        customTitle: e['title'] as String?,
        recovered: meta['status'] == 'recovered',
        deletedAt: e['deleted_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(e['deleted_at'] as int),
        nextN: n + 1,
      );
    } catch (_) {
      return null;
    }
  }
}
