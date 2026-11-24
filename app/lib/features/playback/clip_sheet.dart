import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../app/services.dart';
import '../../data/library.dart';
import 'player.dart';
import 'waveform.dart';

/// "Share clip": 14 s before + 6 s after the mark, adjustable by handles or ±1 s nudges,
/// previewed exactly, exported without re-encoding, then handed to the system share sheet.
class ClipSheet extends StatefulWidget {
  const ClipSheet({super.key, required this.services, required this.recording, required this.mark, required this.peaks});

  final Services services;
  final Recording recording;
  final Mark mark;
  final Uint8List peaks;

  @override
  State<ClipSheet> createState() => _ClipSheetState();
}

class _ClipSheetState extends State<ClipSheet> {
  static const minMs = 1000, maxMs = 10 * 60 * 1000, zoomMs = 60000;

  late int _start, _end;
  late final int _viewStart, _viewEnd;
  Player? _preview;
  bool _exporting = false;
  String? _error;

  Recording get r => widget.recording;

  @override
  void initState() {
    super.initState();
    final w = clipWindow(widget.mark.posMs, r.durationMs);
    _start = w.start;
    _end = w.end;
    _viewStart = math.max(0, math.min(_start, widget.mark.posMs - zoomMs));
    _viewEnd = math.min(r.durationMs, math.max(_end, widget.mark.posMs + zoomMs));
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  void _setStart(int v) => setState(() {
        _start = v.clamp(math.max(0, _end - maxMs), _end - minMs);
      });

  void _setEnd(int v) => setState(() {
        _end = v.clamp(_start + minMs, math.min(r.durationMs, _start + maxMs));
      });

  Future<void> _togglePreview() async {
    final p = _preview ??= widget.services.newPlayer();
    if (p.playing.value) return p.pause();
    await p.open(r.audioPath);
    await p.playRange(_start, _end);
  }

  Future<void> _share() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    await _preview?.pause();
    try {
      final name = clipFileName(r, widget.mark, _start, _end);
      final path = await widget.services.engine.exportClip(r.folder, _start, _end, name);
      await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: 'audio/mp4')], title: name));
    } on PlatformException catch (e) {
      _error = e.message ?? 'The clip could not be made.';
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final len = (_end - _start) / 1000;
    final readout = '${clock(_start)} → ${clock(_end)} · ${len.toStringAsFixed(1)} s';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Share clip · ${widget.mark.name}', style: text.titleMedium),
        const SizedBox(height: Space.xs),
        Semantics(
          liveRegion: true,
          label: 'Clip from ${spokenTime(_start)} to ${spokenTime(_end)}, ${len.toStringAsFixed(1)} seconds',
          child: ExcludeSemantics(
            child: Text(readout, style: text.labelLarge!.copyWith(color: c.text2, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
        const SizedBox(height: Space.l),
        _range(context),
        const SizedBox(height: Space.l),
        Row(children: [
          _Nudge(label: 'Start', onMinus: () => _setStart(_start - 1000), onPlus: () => _setStart(_start + 1000)),
          const Spacer(),
          _Nudge(label: 'End', onMinus: () => _setEnd(_end - 1000), onPlus: () => _setEnd(_end + 1000)),
        ]),
        if (_error != null) ...[
          const SizedBox(height: Space.m),
          Text(_error!, style: text.bodyLarge!.copyWith(color: c.rec)),
        ],
        const SizedBox(height: Space.xl),
        Row(children: [
          Expanded(
            child: _preview == null
                ? SheetButton(label: 'Preview', onTap: _togglePreview)
                : ValueListenableBuilder(
                    valueListenable: _preview!.playing,
                    builder: (context, playing, _) =>
                        SheetButton(label: playing ? 'Stop preview' : 'Preview', onTap: _togglePreview),
                  ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: SheetButton(
              label: _exporting ? 'Making clip…' : 'Share',
              fill: c.text,
              ink: c.bg,
              onTap: _exporting ? null : _share,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _range(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final span = _viewEnd - _viewStart;
      double x(int ms) => (ms - _viewStart) / span * w;
      int dms(double dx) => (dx / w * span).round();
      Widget handle(int ms, String label, ValueChanged<int> set) => Positioned(
            left: x(ms) - kMinTarget / 2,
            top: Waveform.flagArea - 6,
            bottom: -6,
            width: kMinTarget,
            child: Semantics(
              slider: true,
              label: '$label of clip',
              value: clock(ms),
              increasedValue: clock(ms + 1000),
              decreasedValue: clock(math.max(0, ms - 1000)),
              onIncrease: () => set(ms + 1000),
              onDecrease: () => set(ms - 1000),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => set((label == 'Start' ? _start : _end) + dms(d.delta.dx)),
                child: Center(
                  child: Container(
                    width: 6,
                    decoration: BoxDecoration(color: c.accentInk, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          );
      final preview = _preview;
      Widget wave(int pos) => Waveform(
            peaks: widget.peaks,
            durationMs: r.durationMs,
            positionMs: pos,
            marks: [widget.mark],
            viewStartMs: _viewStart,
            viewEndMs: _viewEnd,
            rangeStartMs: _start,
            rangeEndMs: _end,
            height: 112,
          );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          preview == null
              ? wave(-1)
              : ValueListenableBuilder(
                  valueListenable: preview.positionMs,
                  builder: (context, p, _) => wave(preview.playing.value ? _start + p : -1),
                ),
          handle(_start, 'Start', _setStart),
          handle(_end, 'End', _setEnd),
        ],
      );
    });
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.label, required this.onMinus, required this.onPlus});

  final String label;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget chip(String t, String sem, VoidCallback onTap) => PressableScale(
          semanticLabel: sem,
          onTap: onTap,
          child: Container(
            height: kMinTarget,
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(100)),
            child: Text(t, style: text.labelMedium),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ExcludeSemantics(child: Text(label, style: text.labelMedium!.copyWith(color: c.text2))),
      const SizedBox(width: Space.s),
      chip('−1 s', '$label 1 second earlier', onMinus),
      const SizedBox(width: Space.xs),
      chip('+1 s', '$label 1 second later', onPlus),
    ]);
  }
}
