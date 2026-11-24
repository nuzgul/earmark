import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../data/library.dart';

/// Waveform from peaks.bin (one byte per 50 ms) with numbered ribbon flags at the marks.
/// [viewStartMs]..[viewEndMs] zooms (clip sheet); [rangeStartMs]..[rangeEndMs] highlights a clip.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.peaks,
    required this.durationMs,
    required this.positionMs,
    this.marks = const [],
    this.onSeek,
    this.onFlag,
    this.viewStartMs = 0,
    this.viewEndMs,
    this.rangeStartMs,
    this.rangeEndMs,
    this.height = 120,
  });

  static const flagArea = 30.0;
  static const peakMs = 50;

  final Uint8List peaks;
  final int durationMs;
  final int positionMs;
  final List<Mark> marks;
  final ValueChanged<int>? onSeek;
  final ValueChanged<Mark>? onFlag;
  final int viewStartMs;
  final int? viewEndMs;
  final int? rangeStartMs;
  final int? rangeEndMs;
  final double height;

  int get _viewEnd => math.max(viewEndMs ?? durationMs, viewStartMs + 1);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        double x(int ms) => (ms - viewStartMs) / (_viewEnd - viewStartMs) * w;
        int msAt(double dx) => (viewStartMs + dx.clamp(0, w) / w * (_viewEnd - viewStartMs)).round().clamp(0, durationMs);
        final visible = marks.where((m) => !m.system && m.posMs >= viewStartMs && m.posMs <= _viewEnd);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: flagArea,
              child: Semantics(
                slider: true,
                label: 'Position',
                value: '${spokenTime(positionMs)} of ${spokenTime(durationMs)}',
                increasedValue: spokenTime(math.min(positionMs + 10000, durationMs)),
                decreasedValue: spokenTime(math.max(positionMs - 10000, 0)),
                onIncrease: onSeek == null ? null : () => onSeek!(math.min(positionMs + 10000, durationMs)),
                onDecrease: onSeek == null ? null : () => onSeek!(math.max(positionMs - 10000, 0)),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: onSeek == null ? null : (d) => onSeek!(msAt(d.localPosition.dx)),
                  onHorizontalDragUpdate: onSeek == null ? null : (d) => onSeek!(msAt(d.localPosition.dx)),
                  child: CustomPaint(
                    painter: _WavePainter(
                      peaks: peaks,
                      viewStartMs: viewStartMs,
                      viewEndMs: _viewEnd,
                      positionMs: positionMs,
                      rangeStartMs: rangeStartMs,
                      rangeEndMs: rangeEndMs,
                      markMs: [for (final m in marks) if (!m.system) m.posMs],
                      systemMs: [for (final m in marks) if (m.system) m.posMs],
                      colors: c,
                    ),
                  ),
                ),
              ),
            ),
            for (final m in visible)
              Positioned(
                left: x(m.posMs) - kMinTarget / 2,
                top: -9,
                width: kMinTarget,
                height: kMinTarget,
                child: Semantics(
                  button: true,
                  label: '${m.name} at ${spokenTime(m.posMs)}, jump',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onFlag == null ? null : () => onFlag!(m),
                    child: ExcludeSemantics(child: Align(alignment: const Alignment(0, 0.15), child: RibbonFlag(n: m.n))),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Numbered marigold ribbon, the logo's bookmark at flag size.
class RibbonFlag extends StatelessWidget {
  const RibbonFlag({super.key, required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CustomPaint(
      painter: _FlagPainter(c.accent),
      child: SizedBox(
        width: 20,
        height: 26,
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$n',
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling, // the flag is a fixed-size glyph; the list carries the text
            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.onAccent, letterSpacing: 0, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height - 6)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.color != color;
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.peaks,
    required this.viewStartMs,
    required this.viewEndMs,
    required this.positionMs,
    required this.rangeStartMs,
    required this.rangeEndMs,
    required this.markMs,
    required this.systemMs,
    required this.colors,
  });

  final Uint8List peaks;
  final int viewStartMs, viewEndMs, positionMs;
  final int? rangeStartMs, rangeEndMs;
  final List<int> markMs, systemMs;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final span = viewEndMs - viewStartMs;
    double x(int ms) => (ms - viewStartMs) / span * size.width;
    final mid = size.height / 2;

    if (rangeStartMs != null && rangeEndMs != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x(rangeStartMs!), 0, x(rangeEndMs!), size.height), const Radius.circular(6)),
        Paint()..color = colors.accent.withValues(alpha: 0.16),
      );
    }

    const step = 3.0, bar = 2.0;
    final n = (size.width / step).floor();
    final played = Paint()..color = colors.text;
    final rest = Paint()..color = colors.border;
    final inRange = Paint()..color = colors.accentInk;
    for (var i = 0; i < n; i++) {
      final t0 = viewStartMs + span * i ~/ n, t1 = viewStartMs + span * (i + 1) ~/ n;
      var v = 0;
      for (var p = t0 ~/ Waveform.peakMs; p <= (t1 - 1) ~/ Waveform.peakMs && p < peaks.length; p++) {
        if (p >= 0 && peaks[p] > v) v = peaks[p];
      }
      final h = math.max(2.0, math.sqrt(v / 255) * (size.height - 8));
      final ranged = rangeStartMs != null && t0 >= rangeStartMs! && t1 <= rangeEndMs!;
      final paint = ranged ? inRange : (t0 < positionMs ? played : rest);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(i * step + bar / 2, mid), width: bar, height: h), const Radius.circular(1)),
        paint,
      );
    }

    final markLine = Paint()
      ..color = colors.accent
      ..strokeWidth = 1.5;
    for (final ms in markMs) {
      if (ms >= viewStartMs && ms <= viewEndMs) canvas.drawLine(Offset(x(ms), 0), Offset(x(ms), size.height), markLine);
    }
    final systemLine = Paint()
      ..color = colors.text2
      ..strokeWidth = 1;
    for (final ms in systemMs) {
      if (ms >= viewStartMs && ms <= viewEndMs) canvas.drawLine(Offset(x(ms), 4), Offset(x(ms), size.height - 4), systemLine);
    }
    if (positionMs >= viewStartMs && positionMs <= viewEndMs) {
      canvas.drawLine(
        Offset(x(positionMs), 0),
        Offset(x(positionMs), size.height),
        Paint()
          ..color = colors.text
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.positionMs != positionMs ||
      old.rangeStartMs != rangeStartMs ||
      old.rangeEndMs != rangeEndMs ||
      old.viewStartMs != viewStartMs ||
      old.viewEndMs != viewEndMs ||
      old.peaks != peaks ||
      old.markMs.length != markMs.length ||
      old.colors != colors;
}
