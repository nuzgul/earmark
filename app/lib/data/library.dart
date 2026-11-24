import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
  final day = DateTime.utc(t.year, t.month, t.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final diff = today.difference(day).inDays; // UTC dates: a DST day is still one day
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
  String cap(String s, int n) => s.runes.length <= n ? s : '${String.fromCharCodes(s.runes.take(n - 1))}…';
  return '${cap(r.title, 60)} — ${cap(m.name, 40)} (${t(startMs)} to ${t(endMs)}).m4a';
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

  // Settings (settings.json next to the recordings folder).
  bool preRoll = true;
  int preRollSeconds = 3;
  bool calmMode = true;
  List<String> quickLabels = defaultQuickLabels;

  /// Pro, remembered after the store confirmed a purchase or restore. There is no server, so
  /// this local flag is the entitlement (a modified device could fake it; accepted for 5.99).
  bool pro = false;

  static const defaultQuickLabels = ['Idea', 'To-do', 'Quote', 'Question'];
  static const preRollChoices = [3, 5, 10];

  /// How far before a mark playback starts.
  int get preRollMs => preRoll ? preRollSeconds * 1000 : 0;

  List<Recording> get recordings => _all.where((r) => r.deletedAt == null).toList();
  List<Recording> get recentlyDeleted => _all.where((r) => r.deletedAt != null).toList();
  Recording? byId(String id) => _all.where((r) => r.id == id).firstOrNull;

  /// Folders saved while a load was scanning; re-read once it ends so none is lost.
  Set<String>? _upsertedDuringLoad;

  /// Reads every recording on a background isolate (thousands of folders must not stall the
  /// first frame), purging Recently deleted ones past 30 days.
  Future<void> load() async {
    final r = root;
    if (r != null && Directory(r).existsSync()) {
      _upsertedDuringLoad = {};
      final now = _now().millisecondsSinceEpoch;
      const keep = 30 * 24 * 3600 * 1000; // keepDeleted, as a constant the isolate can take
      final found = await Isolate.run(() => _scan(r, now, keep));
      final late = _upsertedDuringLoad!;
      _upsertedDuringLoad = null;
      final byId = {for (final x in found) x.id: x};
      for (final f in late) {
        final x = _read(f);
        if (x != null) byId[x.id] = x;
      }
      _all = byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _applySettings(_settings());
    }
    loaded = true;
    notifyListeners();
  }

  void _applySettings(Map<String, dynamic> st) {
    T? get<T>(String k) => st[k] is T ? st[k] as T : null;
    preRoll = get<bool>('pre_roll') ?? true;
    final s = get<num>('pre_roll_s')?.toInt();
    preRollSeconds = preRollChoices.contains(s) ? s! : 3;
    calmMode = get<bool>('calm') ?? true;
    quickLabels = get<List<dynamic>>('quick_labels')?.whereType<String>().take(4).toList() ?? defaultQuickLabels;
    pro = get<bool>('pro') ?? false;
  }

  /// After the engine saves or recovers a recording.
  void upsert(String folder) {
    _upsertedDuringLoad?.add(folder);
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
    final markId = 'u${_now().microsecondsSinceEpoch}-${_seq++}';
    await _edit(id, (e) {
      // Numbered from the file as it is now, inside the queue: two quick adds get two numbers.
      final n = _nextN(r.folder, e);
      (e['added'] as List).add({'id': markId, 'pos_ms': posMs.clamp(0, r.durationMs), 'n': n});
    });
    return byId(id)!.marks.firstWhere((m) => m.id == markId);
  }

  int _seq = 0;

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

  Future<void> setPreRoll(bool on) => _set('pre_roll', on, () => preRoll = on);
  Future<void> setPreRollSeconds(int s) => _set('pre_roll_s', s, () => preRollSeconds = s);
  Future<void> setCalmMode(bool on) => _set('calm', on, () => calmMode = on);
  Future<void> setQuickLabels(List<String> labels) => _set('quick_labels', labels, () => quickLabels = labels);
  Future<void> setPro(bool on) => _set('pro', on, () => pro = on);

  /// Labels a mark of the recording in progress (quick labels); the library shows it once saved.
  Future<void> labelLiveMark(String recordingId, String markId, String label) async {
    if (root == null) return;
    await _write('$root/$recordingId', (e) => (e['labels'] as Map)[markId] = label);
    if (byId(recordingId) != null) upsert('$root/$recordingId'); // saved meanwhile
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

  Future<void> _set(String key, Object value, void Function() apply) async {
    apply();
    notifyListeners();
    if (root == null) return;
    final f = _settingsFile();
    await _serial(f.path, () async {
      // Before the first load the in-memory values are only defaults: change just this key.
      final data = loaded
          ? {..._settings(), 'pre_roll': preRoll, 'pre_roll_s': preRollSeconds, 'calm': calmMode, 'quick_labels': quickLabels, 'pro': pro}
          : {..._settings(), key: value};
      await _atomicWrite(f, jsonEncode(data));
    });
  }

  Map<String, dynamic> _settings() => _readJson(_settingsFile()) ?? {};

  Future<void> _edit(String id, void Function(Map<String, dynamic>) change) async {
    final r = byId(id);
    if (r == null) return;
    await _write(r.folder, change);
    upsert(r.folder);
  }

  /// One read-modify-write at a time per file, so quick successive edits never overwrite each other.
  Future<void> _write(String folder, void Function(Map<String, dynamic>) change) {
    final f = File('$folder/library.json');
    return _serial(f.path, () async {
      final e = _edits(folder);
      change(e);
      await _atomicWrite(f, jsonEncode(e));
    });
  }

  final _queues = <String, Future<void>>{};

  Future<T> _serial<T>(String key, Future<T> Function() job) {
    final run = (_queues[key] ?? Future<void>.value()).then((_) => job());
    _queues[key] = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<void> _atomicWrite(File f, String text) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path); // atomic: a crash never leaves half a file
  }

  int _nextN(String folder, Map<String, dynamic> e) => _read(folder)?.nextN ?? 1;

  Recording? _read(String folder) => _readRecording(folder);
}

/// Background-isolate scan for [LibraryStore.load].
List<Recording> _scan(String root, int nowMs, int keepMs) {
  final out = <Recording>[];
  for (final d in Directory(root).listSync().whereType<Directory>()) {
    try {
      final r = _readRecording(d.path);
      if (r == null) continue;
      if (r.deletedAt != null && nowMs - r.deletedAt!.millisecondsSinceEpoch > keepMs) {
        d.deleteSync(recursive: true); // the 30 days in Recently deleted are over
        continue;
      }
      out.add(r);
    } catch (_) {
      // One unreadable or undeletable folder must not hide the others.
    }
  }
  return out;
}

/// A JSON object from [f]; null when missing. A damaged file is kept aside (".damaged") and
/// what can be saved is used: a stray tail after the last complete object is dropped.
Map<String, dynamic>? _readJson(File f) {
  final String text;
  try {
    text = f.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    try {
      final copy = File('${f.path}.damaged');
      if (!copy.existsSync()) f.copySync(copy.path);
    } catch (_) {}
    for (var i = text.lastIndexOf('}'); i > 0 && i > text.length - 512; i = text.lastIndexOf('}', i - 1)) {
      try {
        return jsonDecode(text.substring(0, i + 1)) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }
}

Map<String, dynamic> _edits(String folder) {
  final e = _readJson(File('$folder/library.json')) ?? <String, dynamic>{};
  if (e['labels'] is! Map) e['labels'] = <String, dynamic>{};
  if (e['deleted'] is! List) e['deleted'] = <dynamic>[];
  if (e['added'] is! List) e['added'] = <dynamic>[];
  return e;
}

/// Null for folders that are not a finished recording (in progress, or audio missing).
Recording? _readRecording(String folder) {
    try {
      if (!File('$folder/audio.m4a').existsSync()) return null;
      final meta = jsonDecode(File('$folder/meta.json').readAsStringSync()) as Map<String, dynamic>;
      // Marks are journaled at once, audio every few seconds: after a power loss a mark can sit
      // past the recovered audio. Show it at the end instead.
      final durationMs = meta['duration_ms'] as int;
      int fit(int ms) => durationMs > 0 && ms > durationMs ? durationMs : ms;
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
          posMs: fit((j['pos_frames'] as int) * 1000 ~/ (j['sample_rate'] as int)),
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
        durationMs: durationMs,
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
