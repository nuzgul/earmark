import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../app/services.dart';
import '../../data/library.dart';
import '../pro/pro.dart';
import 'batch_sheet.dart';
import 'clip_sheet.dart';
import 'player.dart';
import 'waveform.dart';

/// One recording: waveform with flags, transport, marks with Share clip, + Mark at the playhead.
class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key, required this.services, required this.recordingId, this.startAt});

  final Services services;
  final String recordingId;

  /// Opened from a search hit: jump there (with pre-roll) once loaded.
  final Mark? startAt;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  late final Player player = widget.services.newPlayer();
  LibraryStore get lib => widget.services.library;
  Uint8List _peaks = Uint8List(0);

  /// The file opens asynchronously; every seek and play waits for it, so a flag tapped
  /// right after the screen opens still jumps instead of being lost.
  Future<void> _opening = Future.value();

  static const speeds = [1.0, 1.5, 2.0];
  double _speed = 1;

  Future<void> _nextSpeed() async {
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    setState(() => _speed = next);
    await player.setSpeed(next);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = lib.byId(widget.recordingId);
    if (r == null) return;
    try {
      _peaks = File(r.peaksPath).readAsBytesSync(); // one byte per 50 ms: 72 KB for an hour
    } on FileSystemException {
      // No waveform (old or damaged file): flat bars, everything else still works.
    }
    _opening = player.open(r.audioPath);
    await _opening;
    if (widget.startAt != null) await _jump(widget.startAt!);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  int get _preRoll => lib.preRollMs;

  Future<void> _seek(int ms) async {
    await _opening;
    await player.seek(ms);
  }

  Future<void> _play() async {
    await _opening;
    await player.play();
  }

  Future<void> _jump(Mark m) async {
    await _seek((m.posMs - _preRoll).clamp(0, 1 << 31));
    await _play();
  }

  Future<void> _skip(int deltaMs, Recording r) => _seek((player.positionMs.value + deltaMs).clamp(0, r.durationMs));

  Future<void> _nextMark(Recording r, {required bool forward}) async {
    final ref = player.positionMs.value + _preRoll;
    final marks = r.userMarks;
    final m = forward
        ? marks.where((m) => m.posMs > ref + 250).firstOrNull
        : marks.where((m) => m.posMs < ref - 1500).lastOrNull;
    if (m != null) await _jump(m);
  }

  void _say(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _addMark(Recording r) async {
    final m = await lib.addMark(r.id, player.positionMs.value);
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), '${m.name} added at ${spokenTime(m.posMs)}', TextDirection.ltr);
    _say('${m.name} added at ${clock(m.posMs)}');
  }

  Future<void> _markMenu(Recording r, Mark m) async {
    final a = await chooseAction<String>(context, [
      (label: 'Rename mark', value: 'rename', danger: false),
      (label: 'Delete mark', value: 'delete', danger: true),
    ]);
    if (!mounted) return;
    if (a == 'rename') {
      final t = await askText(context, title: 'Rename ${m.name}', initial: m.label ?? '', hint: 'Mark ${m.n}');
      if (t != null) await lib.renameMark(r.id, m.id, t);
    }
    if (a == 'delete') {
      await lib.deleteMark(r.id, m.id);
      _say('${m.name} deleted', action: SnackBarAction(label: 'Undo', onPressed: () => lib.undoDeleteMark(r.id, m.id)));
    }
  }

  Future<void> _menu(Recording r) async {
    final a = await chooseAction<String>(context, [
      if (r.userMarks.isNotEmpty) (label: 'Share several clips', value: 'batch', danger: false),
      (label: 'Rename recording', value: 'rename', danger: false),
      (label: 'Delete recording', value: 'delete', danger: true),
    ]);
    if (!mounted) return;
    if (a == 'batch' && await requirePro(context, widget.services.pro) && mounted) {
      await player.pause();
      if (mounted) await showAppSheet<void>(context, (_) => BatchClipSheet(services: widget.services, recording: r));
    }
    if (a == 'rename') await _rename(r);
    if (a == 'delete' && mounted) {
      final n = r.userMarks.length;
      final ok = await confirm(
        context,
        title: 'Delete "${r.title}"?',
        message: 'The ${clock(r.durationMs)} recording and its $n ${n == 1 ? 'mark' : 'marks'} move to Recently deleted for 30 days.',
        action: 'Delete recording',
      );
      if (!ok || !mounted) return;
      await player.pause();
      await lib.delete(r.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _rename(Recording r) async {
    final t = await askText(context, title: 'Rename recording', initial: r.title);
    if (t != null) await lib.rename(r.id, t);
  }

  Future<void> _clip(Recording r, Mark m) async {
    await player.pause();
    if (!mounted) return;
    await showAppSheet<void>(context, (_) => ClipSheet(services: widget.services, recording: r, mark: m, peaks: _peaks));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final r = lib.byId(widget.recordingId);
        if (r == null) return const Scaffold();
        final marks = r.userMarks;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
                  child: Row(children: [
                    IconTap(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.pop(context)),
                    const Spacer(),
                    _SpeedChip(speed: _speed, onTap: _nextSpeed),
                    IconTap(icon: Icons.more_horiz_rounded, label: 'More for this recording', onTap: () => _menu(r)),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Space.screen, Space.s, Space.screen, Space.l),
                    children: [
                      PressableScale(
                        semanticLabel: 'Rename recording, ${r.title}',
                        onTap: () => _rename(r),
                        child: Text(r.title, style: text.headlineSmall),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        '${longDate(r.createdAt)} · ${hourMinute(r.createdAt)} · ${clock(r.durationMs)} · '
                        '${marks.length} ${marks.length == 1 ? 'mark' : 'marks'}${r.recovered ? ' · Recovered' : ''}',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: Space.xxl),
                      ValueListenableBuilder(
                        valueListenable: player.positionMs,
                        builder: (context, pos, _) => Column(
                          children: [
                            Waveform(
                              peaks: _peaks,
                              durationMs: r.durationMs,
                              positionMs: pos,
                              marks: r.marks,
                              onSeek: _seek,
                              onFlag: _jump,
                            ),
                            const SizedBox(height: Space.s),
                            Row(children: [
                              Text(clock(pos), key: const ValueKey('playhead'), style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                              const Spacer(),
                              Text(clock(r.durationMs), style: text.labelLarge!.copyWith(color: c.text2, fontFeatures: const [FontFeature.tabularFigures()])),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.l),
                      _Transport(
                        player: player,
                        onPlay: _play,
                        onPrev: marks.isEmpty ? null : () => _nextMark(r, forward: false),
                        onNext: marks.isEmpty ? null : () => _nextMark(r, forward: true),
                        onBack: () => _skip(-10000, r),
                        onForward: () => _skip(10000, r),
                      ),
                      const SizedBox(height: Space.l),
                      MergeSemantics(
                        child: Row(children: [
                          Expanded(child: Text('Start ${lib.preRollSeconds} s before a mark', style: text.bodyLarge)),
                          Switch(value: lib.preRoll, onChanged: lib.setPreRoll),
                        ]),
                      ),
                      const SizedBox(height: Space.l),
                      if (marks.isEmpty)
                        Text('No marks yet. Play and tap "+ Mark" where it matters.', style: text.bodyLarge!.copyWith(color: c.text2))
                      else
                        for (final m in marks) ...[
                          _MarkLine(
                            mark: m,
                            onJump: () => _jump(m),
                            onClip: () => _clip(r, m),
                            onMenu: () => _markMenu(r, m),
                          ),
                          const SizedBox(height: Space.s),
                        ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.screen, Space.s, Space.screen, Space.l),
                  child: ValueListenableBuilder(
                    valueListenable: player.positionMs,
                    builder: (context, pos, _) => SheetButton(
                      label: '+ Mark at ${clock(pos)}',
                      fill: c.accent,
                      ink: c.onAccent,
                      onTap: () => _addMark(r),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.player, required this.onPlay, required this.onPrev, required this.onNext, required this.onBack, required this.onForward});

  final Player player;
  final VoidCallback onPlay;
  final VoidCallback? onPrev, onNext;
  final VoidCallback onBack, onForward;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget small(IconData icon, String label, VoidCallback? onTap) {
      final circle = SizedBox.square(
        dimension: 56,
        child: Icon(icon, size: 28, color: onTap == null ? c.border : c.text),
      );
      return onTap == null
          ? Semantics(button: true, enabled: false, label: label, child: ExcludeSemantics(child: circle))
          : PressableScale(semanticLabel: label, onTap: onTap, child: circle);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        small(Icons.skip_previous_rounded, 'Previous mark', onPrev),
        small(Icons.replay_10_rounded, 'Back 10 seconds', onBack),
        ValueListenableBuilder(
          valueListenable: player.playing,
          builder: (context, playing, _) => PressableScale(
            semanticLabel: playing ? 'Pause' : 'Play',
            onTap: playing ? player.pause : onPlay,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.text),
              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36, color: c.bg),
            ),
          ),
        ),
        small(Icons.forward_10_rounded, 'Forward 10 seconds', onForward),
        small(Icons.skip_next_rounded, 'Next mark', onNext),
      ],
    );
  }
}

class _MarkLine extends StatelessWidget {
  const _MarkLine({required this.mark, required this.onJump, required this.onClip, required this.onMenu});

  final Mark mark;
  final VoidCallback onJump, onClip, onMenu;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final jump = PressableScale(
      semanticLabel: 'Play from ${mark.name} at ${spokenTime(mark.posMs)}',
      onTap: onJump,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        child: Row(children: [
          RibbonFlag(n: mark.n),
          const SizedBox(width: Space.m),
          Text(clock(mark.posMs), style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: Space.m),
          Expanded(child: Text(mark.name, style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
    final clip = PressableScale(
      semanticLabel: 'Share clip of ${mark.name}',
      onTap: onClip,
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), border: Border.all(color: c.accentInk)),
          child: Text('Share clip', style: text.labelMedium!.copyWith(color: c.accentInk)),
        ),
      ),
    );
    final menu = IconTap(icon: Icons.more_horiz_rounded, label: 'More for ${mark.name}', onTap: onMenu, color: c.text2);
    // Large text: the actions move under the mark instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 22;
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
      padding: const EdgeInsets.only(left: Space.xs),
      child: stacked
          ? Column(children: [jump, Row(mainAxisAlignment: MainAxisAlignment.end, children: [clip, menu])])
          : Row(children: [Expanded(child: jump), clip, menu]),
    );
  }
}

/// 1× → 1.5× → 2×, for long recordings.
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.speed, required this.onTap});

  final double speed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final label = speed == speed.roundToDouble() ? '${speed.round()}×' : '$speed×';
    return PressableScale(
      semanticLabel: 'Playback speed $label. Change',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: kMinTarget, minHeight: kMinTarget),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), border: Border.all(color: c.border)),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ),
    );
  }
}
