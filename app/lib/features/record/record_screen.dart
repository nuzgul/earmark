import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../engine/engine_api.g.dart';
import '../../engine/engine_client.dart';
import 'widgets.dart';

/// Home screen: idle (Record) and live (timer, marks, Bookmark zone). Everything shown
/// comes from the engine's snapshot; nothing here assumes a state the engine did not report.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.engine});

  final EngineClient engine;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  EngineClient get engine => widget.engine;

  /// Set when the microphone was refused; "permanent" means only Settings can fix it.
  String? _micDenied;
  bool _busy = false;
  String? _glowId;
  Timer? _glowTimer;

  @override
  void initState() {
    super.initState();
    engine.refresh();
    engine.recover();
    engine.marks.addListener(_onMarks);
  }

  @override
  void dispose() {
    engine.marks.removeListener(_onMarks);
    _glowTimer?.cancel();
    super.dispose();
  }

  void _onMarks() {
    final list = engine.marks.value;
    if (list.isEmpty || list.last.id == _glowId) return;
    final m = list.last;
    setState(() => _glowId = m.id);
    _glowTimer?.cancel();
    _glowTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _glowId = null);
    });
    SemanticsService.sendAnnouncement(View.of(context), 'Mark ${m.index} at ${spokenTime(m.positionMs)}', TextDirection.ltr);
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _record() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await engine.start();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _micDenied = error?.code == 'mic_denied' ? (error!.details as String? ?? 'ask') : null;
    });
    if (error != null && error.code != 'mic_denied') _say(error.message ?? 'Recording could not start.');
  }

  Future<void> _stop() async {
    final saved = await engine.stop();
    if (!mounted) return;
    if (saved == null) _say("Couldn't finish saving. Earmark will complete it the next time it opens.");
  }

  Future<void> _mark() async {
    final m = await engine.mark();
    if (m == null && mounted) _say('Nothing is recording.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: engine.snapshot,
          builder: (context, s, _) => s.state == SessionState.idle ? _idle(s) : _live(s),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- idle

  Widget _idle(EngineSnapshot s) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, Space.xxxl, Space.screen, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The 76 sp timer shrinks to fit instead of wrapping at big text sizes.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('00:00', maxLines: 1, style: text.displayLarge!.copyWith(color: c.text2)),
          ),
          const SizedBox(height: Space.s),
          Text(
            s.freeBytes > 0 ? 'Ready to record · ${spaceLeft(s.freeBytes)}' : 'Ready to record',
            style: text.bodyLarge!.copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.xl),
          ValueListenableBuilder(
            valueListenable: engine.lastSaved,
            builder: (context, r, _) => r == null ? const SizedBox.shrink() : _SavedStrip(recording: r),
          ),
          if (_micDenied != null) ...[
            const SizedBox(height: Space.m),
            _MicCard(permanent: _micDenied == 'permanent', onSettings: engine.openAppSettings, onRetry: _record),
          ],
          const Spacer(),
          Center(
            child: PressableScale(
              semanticLabel: 'Start recording',
              pressedScale: 0.95,
              onTap: _record,
              child: _RecordButton(colors: c, busy: _busy),
            ),
          ),
          const SizedBox(height: Space.m),
          Center(child: ExcludeSemantics(child: Text('Record', style: text.labelLarge))),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- live

  Widget _live(EngineSnapshot s) {
    return ValueListenableBuilder(
      valueListenable: engine.stale,
      builder: (context, stale, _) => ValueListenableBuilder(
        valueListenable: engine.marks,
        builder: (context, marks, _) => LayoutBuilder(
          builder: (context, box) {
            final landscape = box.maxWidth > box.maxHeight;
            final info = _liveInfo(s, stale, marks);
            final zone = BookmarkZone(onMark: _mark, enabled: _canMark(s));
            if (landscape) {
              return Padding(
                padding: const EdgeInsets.all(Space.screen),
                child: Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: Space.xl),
                    Expanded(child: zone),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.l, Space.screen, Space.screen),
              child: Column(
                children: [
                  Expanded(child: info),
                  const SizedBox(height: Space.l),
                  SizedBox(height: (box.maxHeight * 0.42).clamp(200, 420), child: zone),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _canMark(EngineSnapshot s) =>
      s.state == SessionState.recording || s.state == SessionState.paused || s.state == SessionState.interrupted;

  Widget _liveInfo(EngineSnapshot s, bool stale, List<MarkResult> marks) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final capturing = s.state == SessionState.recording && !stale;
    final paused = s.state == SessionState.paused;
    final label = stale
        ? 'Checking microphone…'
        : switch (s.state) {
            SessionState.starting => 'Starting…',
            SessionState.recording => 'Recording',
            SessionState.paused => 'Paused',
            SessionState.interrupted => s.interruption == 'call' ? 'Paused: call' : 'Checking microphone…',
            SessionState.finalizing => 'Saving…',
            SessionState.idle => '',
          };
    final recent = marks.reversed.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatePill(label: label, live: capturing),
            const Spacer(),
            Semantics(
              label: '${s.markCount} ${s.markCount == 1 ? 'mark' : 'marks'}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    RibbonGlyph(color: c.accentInk, size: 16),
                    const SizedBox(width: Space.s),
                    RollingCount(value: s.markCount, style: text.labelLarge!),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        Semantics(
          label: 'Recorded ${spokenTime(s.positionMs)}',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(clock(s.positionMs), maxLines: 1, style: text.displayLarge!.copyWith(color: capturing ? c.text : c.text2)),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        LevelLine(level: capturing ? s.level : 0),
        const SizedBox(height: Space.xl),
        // Takes what is left, so large text never pushes the controls off screen.
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final m in recent) ...[
                MarkRow(mark: m, highlight: m.id == _glowId),
                const SizedBox(height: Space.s),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            paused
                ? RoundControl(icon: Icons.play_arrow_rounded, caption: 'Resume', semanticLabel: 'Resume recording', onTap: engine.resume)
                : RoundControl(
                    icon: Icons.pause_rounded,
                    caption: 'Pause',
                    semanticLabel: 'Pause recording',
                    onTap: _canMark(s) ? engine.pause : null,
                  ),
            RoundControl(
              icon: Icons.stop_rounded,
              caption: 'Stop',
              semanticLabel: 'Stop and save',
              iconColor: c.rec,
              onTap: s.state == SessionState.finalizing ? null : _stop,
            ),
          ],
        ),
      ],
    );
  }
}

class _SavedStrip extends StatelessWidget {
  const _SavedStrip({required this.recording});

  final SavedRecording recording;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final n = recording.marks.length;
    final what = recording.recovered ? 'Recovered' : 'Saved';
    final detail = '${clock(recording.durationMs)} · $n ${n == 1 ? 'mark' : 'marks'}';
    return Semantics(
      label: '$what recording, $detail',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: c.success),
              const SizedBox(width: Space.m),
              Text(what, style: text.labelLarge),
              const SizedBox(width: Space.s),
              Expanded(child: Text(detail, style: text.bodyLarge!.copyWith(color: c.text2))),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicCard extends StatelessWidget {
  const _MicCard({required this.permanent, required this.onSettings, required this.onRetry});

  final bool permanent;
  final VoidCallback onSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Microphone is off for Earmark', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            permanent
                ? 'Turn on the microphone in Settings to record. Your recordings stay on this phone.'
                : 'Earmark needs the microphone to record. Your recordings stay on this phone.',
            style: text.bodyLarge!.copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.m),
          PressableScale(
            semanticLabel: permanent ? 'Open Settings' : 'Allow microphone',
            onTap: permanent ? onSettings : onRetry,
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTarget),
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(100)),
              alignment: Alignment.center,
              child: Text(permanent ? 'Open Settings' : 'Allow microphone', style: text.labelLarge),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.colors, required this.busy});

  final AppColors colors;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colors.border, width: 2)),
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.pressIn),
        width: busy ? 84 : 96,
        height: busy ? 84 : 96,
        decoration: BoxDecoration(shape: BoxShape.circle, color: busy ? colors.rec.withValues(alpha: 0.6) : colors.rec),
      ),
    );
  }
}
