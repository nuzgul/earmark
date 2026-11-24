import 'package:flutter/material.dart';

import '../../app/design/leave_out.dart';
import '../../app/design/pressable_scale.dart';
import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../app/services.dart';
import '../../data/library.dart';
import '../playback/playback_screen.dart';
import '../record/widgets.dart';

/// All recordings, grouped by day, with one search over titles and marks.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.services});

  final Services services;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _query = TextEditingController();

  /// Rows swiped away: hidden at once (a dismissed row must leave the tree before the file write ends).
  final _hidden = <String>{};

  /// Rows on their way out after Delete from the menu (a swipe animates by itself).
  final _leaving = <String>{};
  LibraryStore get lib => widget.services.library;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(Recording r, {Mark? at}) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlaybackScreen(services: widget.services, recordingId: r.id, startAt: at),
      ));

  Future<void> _rename(Recording r) async {
    final t = await askText(context, title: 'Rename recording', initial: r.title);
    if (t != null) await lib.rename(r.id, t);
  }

  Future<void> _delete(Recording r) async {
    try {
      await lib.delete(r.id);
    } finally {
      // The library hides it from now on; keeping it here would also hide it after a Restore.
      _hidden.remove(r.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Moved to Recently deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _hidden.remove(r.id);
            lib.restore(r.id);
          },
        ),
      ));
  }

  Future<void> _rowMenu(Recording r) async {
    final a = await chooseAction<String>(context, [
      (label: 'Rename', value: 'rename', danger: false),
      (label: 'Delete', value: 'delete', danger: true),
    ]);
    if (a == 'rename') await _rename(r);
    if (a == 'delete') {
      if (!mounted) return;
      final leave = leaveTime(context);
      setState(() => _leaving.add(r.id));
      if (leave > Duration.zero) await Future<void>.delayed(leave);
      if (!mounted) return;
      // Hidden before it stops leaving, so the collapsed row never grows back while the delete runs.
      setState(() {
        _leaving.remove(r.id);
        _hidden.add(r.id);
      });
      await _delete(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([lib, _query]),
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      IconTap(icon: Icons.arrow_back_rounded, label: 'Back to Record', onTap: () => Navigator.pop(context)),
                      const Spacer(),
                      if (lib.recentlyDeleted.isNotEmpty)
                        IconTap(
                          icon: Icons.delete_outline_rounded,
                          label: 'Recently deleted',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => RecentlyDeletedScreen(library: lib),
                          )),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.screen, Space.s, Space.screen, Space.l),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Library', style: text.headlineLarge),
                      const SizedBox(height: Space.l),
                      TextField(
                        controller: _query,
                        style: text.bodyLarge,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search titles and marks',
                          hintStyle: text.bodyLarge!.copyWith(color: c.text2),
                          prefixIcon: Icon(Icons.search_rounded, color: c.text2),
                          suffixIcon: _query.text.isEmpty
                              ? null
                              : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close_rounded), onPressed: _query.clear),
                          filled: true,
                          fillColor: c.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: Space.l),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ..._content(context),
              const SliverToBoxAdapter(child: SizedBox(height: Space.xxxl)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (!lib.loaded) return const [];
    final q = _query.text.trim();
    if (q.isNotEmpty) {
      final hits = lib.search(q);
      if (hits.isEmpty) return [_empty('Nothing matches "$q"', 'Search looks in titles, mark names and times such as 04:32.')];
      return [
        if (hits.marks.isNotEmpty) ...[
          _header('Matching marks'),
          SliverList.list(children: [
            for (final h in hits.marks) _MarkHit(hit: h, query: q, onTap: () => _open(h.recording, at: h.mark)),
          ]),
        ],
        if (hits.recordings.isNotEmpty) ...[
          _header('Recordings'),
          SliverList.list(children: [for (final r in hits.recordings) _row(r)]),
        ],
      ];
    }
    final all = lib.recordings.where((r) => !_hidden.contains(r.id)).toList();
    if (all.isEmpty) {
      return [_empty('No recordings yet', 'Tap Record. While it records, tap the yellow Bookmark area whenever something matters. Your marks show up here.')];
    }
    final now = lib.now();
    final groups = <String, List<Recording>>{};
    for (final r in all) {
      groups.putIfAbsent(dayGroup(r.createdAt, now), () => []).add(r);
    }
    return [
      for (final g in groups.entries) ...[
        _header(g.key),
        SliverList.list(children: [for (final r in g.value) _row(r)]),
      ],
    ];
  }

  Widget _header(String label) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(Space.screen, Space.l, Space.screen, Space.s),
        sliver: SliverToBoxAdapter(
          child: Semantics(
            header: true,
            child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall!.copyWith(color: AppColors.of(context).text2)),
          ),
        ),
      );

  Widget _empty(String title, String body) => SliverPadding(
        padding: const EdgeInsets.all(Space.screen),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RibbonGlyph(color: AppColors.of(context).accentInk, size: 28),
              const SizedBox(height: Space.l),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Space.s),
              Text(body, style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: AppColors.of(context).text2)),
            ],
          ),
        ),
      );

  Widget _row(Recording r) {
    return LeaveOut(
      key: ValueKey('leave-${r.id}'),
      leaving: _leaving.contains(r.id),
      child: _swipe(r),
    );
  }

  Widget _swipe(Recording r) {
    return Dismissible(
      key: ValueKey('rec-${r.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        color: AppColors.of(context).raised,
        child: Text('Delete', style: Theme.of(context).textTheme.labelLarge!.copyWith(color: AppColors.of(context).rec)),
      ),
      onDismissed: (_) {
        setState(() => _hidden.add(r.id));
        _delete(r);
      },
      child: RecordingRow(recording: r, onTap: () => _open(r), onMenu: () => _rowMenu(r)),
    );
  }
}

class RecordingRow extends StatelessWidget {
  const RecordingRow({super.key, required this.recording, required this.onTap, this.onMenu, this.subtitle});

  final Recording recording;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final r = recording;
    final n = r.userMarks.length;
    // A date title already says when; then the subtitle gives only the length.
    final when = r.customTitle == null ? '' : '${hourMinute(r.createdAt)} · ';
    final sub = subtitle ?? '$when${clock(r.durationMs)}${r.recovered ? ' · Recovered' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: PressableScale(
              semanticLabel: '${r.title}, $sub, $n ${n == 1 ? 'mark' : 'marks'}',
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.m),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(sub, style: text.bodySmall),
                        ],
                      ),
                    ),
                    if (n > 0) ...[
                      const SizedBox(width: Space.m),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
                        decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(100)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          RibbonGlyph(color: c.onAccent, size: 12),
                          const SizedBox(width: Space.xs),
                          Text('$n', style: text.labelMedium!.copyWith(color: c.onAccent)),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (onMenu != null) IconTap(icon: Icons.more_horiz_rounded, label: 'More for ${r.title}', onTap: onMenu!, color: c.text2),
        ],
      ),
    );
  }
}

class _MarkHit extends StatelessWidget {
  const _MarkHit({required this.hit, required this.query, required this.onTap});

  final ({Recording recording, Mark mark}) hit;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final m = hit.mark;
    final name = m.name;
    // Lower-casing can change the length ("İ"): then highlight nothing rather than mis-cut.
    final lower = name.toLowerCase();
    final i = lower.length == name.length ? lower.indexOf(query.toLowerCase()) : -1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 2),
      child: PressableScale(
        semanticLabel: '${m.name} at ${spokenTime(m.posMs)}, in ${hit.recording.title}',
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.m),
          child: Row(
            children: [
              RibbonGlyph(color: c.accentInk, size: 16),
              const SizedBox(width: Space.m),
              Text(clock(m.posMs), style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      i < 0
                          ? TextSpan(text: name)
                          : TextSpan(children: [
                              TextSpan(text: name.substring(0, i)),
                              TextSpan(
                                text: name.substring(i, i + query.length),
                                style: TextStyle(color: c.accentInk, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: name.substring(i + query.length)),
                            ]),
                      style: text.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(hit.recording.title, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deleted recordings stay 30 days, then go for good.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key, required this.library});

  final LibraryStore library;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final items = library.recentlyDeleted;
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
                  child: Row(children: [IconTap(icon: Icons.arrow_back_rounded, label: 'Back to Library', onTap: () => Navigator.pop(context))]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.screen, Space.s, Space.screen, Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recently deleted', style: text.headlineLarge),
                      const SizedBox(height: Space.s),
                      Text('Kept for 30 days, then removed for good.', style: text.bodyLarge!.copyWith(color: AppColors.of(context).text2)),
                    ],
                  ),
                ),
                for (final r in items)
                  RecordingRow(
                    recording: r,
                    subtitle: 'Removed for good in ${_daysLeft(r)} · ${clock(r.durationMs)}',
                    onTap: () => _menu(context, r),
                    onMenu: () => _menu(context, r),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _daysLeft(Recording r) {
    final left = LibraryStore.keepDeleted - library.now().difference(r.deletedAt!);
    final d = left.inDays.clamp(0, 30);
    return d <= 1 ? '1 day' : '$d days';
  }

  Future<void> _menu(BuildContext context, Recording r) async {
    final a = await chooseAction<String>(context, [
      (label: 'Restore', value: 'restore', danger: false),
      (label: 'Delete now', value: 'delete', danger: true),
    ]);
    if (!context.mounted) return;
    if (a == 'restore') await library.restore(r.id);
    if (a == 'delete' && context.mounted) {
      final n = r.userMarks.length;
      final ok = await confirm(
        context,
        title: 'Delete "${r.title}" for good?',
        message: 'The ${clock(r.durationMs)} recording and its $n ${n == 1 ? 'mark' : 'marks'} will be removed from this phone. This can\'t be undone.',
        action: 'Delete for good',
      );
      if (ok) await library.deleteForever(r.id);
    }
  }
}
