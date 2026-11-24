import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../engine/engine_api.g.dart';

/// Red dot + state words. Red appears only while audio is really being captured.
class StatePill extends StatelessWidget {
  const StatePill({super.key, required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(100)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: live ? c.rec : c.text2),
              ),
              const SizedBox(width: Space.s),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thin line whose filled width follows the input level: quick to rise, slow to fall.
class LevelLine extends StatelessWidget {
  const LevelLine({super.key, required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ExcludeSemantics(
      child: Container(
        height: 4,
        decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(2)),
        alignment: Alignment.centerLeft,
        child: _Level(level: level, color: c.text2),
      ),
    );
  }
}

class _Level extends StatefulWidget {
  const _Level({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  State<_Level> createState() => _LevelState();
}

class _LevelState extends State<_Level> {
  double _from = 0;

  @override
  void didUpdateWidget(_Level old) {
    super.didUpdateWidget(old);
    _from = old.level;
  }

  @override
  Widget build(BuildContext context) {
    final rising = widget.level >= _from;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.level.clamp(0, 1)),
      duration: Motion.of(context, Duration(milliseconds: rising ? 50 : 300)),
      curve: Curves.easeOut,
      // A transform, not a width: 20 updates a second for hours must not re-layout (expensive B8).
      builder: (context, v, child) => Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.diagonal3Values(v, 1, 1),
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
        child: const SizedBox(height: 4, width: double.infinity),
      ),
    );
  }
}

/// A number that rolls up when it changes (count roll, 200 ms).
class RollingCount extends StatelessWidget {
  const RollingCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.countRoll),
      transitionBuilder: (child, anim) => ClipRect(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
      ),
      child: Text('$value', key: ValueKey(value), style: style),
    );
  }
}

/// The bookmark ribbon from the logo, as a small glyph.
class RibbonGlyph extends StatelessWidget {
  const RibbonGlyph({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 0.7, size), painter: _RibbonPainter(color));
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height * 0.78)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

/// The big marigold target. Marks on touch-down (raw pointer, so no gesture-arena delay).
/// With quick labels (Pro), holding it opens an arc of labels above the finger: slide to one and
/// let go to label the mark that the touch-down already made, so the timing stays exact.
class BookmarkZone extends StatefulWidget {
  const BookmarkZone({super.key, required this.onMark, required this.enabled, this.labels = const [], this.onLabel});

  final Future<MarkResult?> Function() onMark;
  final bool enabled;
  final List<String> labels;
  final void Function(MarkResult mark, String label)? onLabel;

  static const hold = Duration(milliseconds: 450);

  @override
  State<BookmarkZone> createState() => _BookmarkZoneState();
}

class _BookmarkZoneState extends State<BookmarkZone> {
  int? _pointer;
  Offset _finger = Offset.zero;
  Offset? _arcAt;
  int? _hover;
  Timer? _holdTimer;
  Future<MarkResult?>? _pending;
  Size _size = Size.zero;

  List<String> get _labels => widget.labels.where((l) => l.isNotEmpty).take(4).toList();

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(BookmarkZone old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _pointer != null) {
      // Disabled mid-touch: the Listener goes away and its pointer-up with it.
      _holdTimer?.cancel();
      _pointer = null;
      _arcAt = null;
      _hover = null;
    }
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled) return;
    if (_pointer != null) {
      // Another finger: mark too (only the first one can open the label arc).
      HapticFeedback.mediumImpact();
      widget.onMark();
      return;
    }
    _pointer = e.pointer;
    HapticFeedback.mediumImpact(); // same frame as the visual change
    setState(() => _finger = e.localPosition);
    _pending = widget.onMark();
    if (_labels.isEmpty) return;
    _holdTimer = Timer(BookmarkZone.hold, () {
      if (!mounted || _pointer == null) return;
      HapticFeedback.selectionClick();
      setState(() => _arcAt = _finger);
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _finger = e.localPosition;
    if (_arcAt == null) return;
    final h = _hit(_finger);
    if (h != _hover) {
      if (h != null) HapticFeedback.selectionClick();
      setState(() => _hover = h);
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final pick = e is PointerUpEvent && _arcAt != null ? _hover : null;
    _holdTimer?.cancel();
    setState(() {
      _pointer = null;
      _arcAt = null;
      _hover = null;
    });
    if (pick != null) _label(_labels[pick], _pending);
  }

  Future<void> _label(String label, Future<MarkResult?>? mark) async {
    final m = await mark;
    if (m != null) widget.onLabel?.call(m, label);
  }

  /// Chip centres on an arc above where the hold began (below it when there is no room above),
  /// spaced so 96 dp chips never overlap, and kept inside the zone.
  List<Offset> _centres() {
    final o = _arcAt!;
    final n = _labels.length;
    const r = 150.0;
    final below = o.dy < r + 24;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.5 : i / (n - 1);
      final a = math.pi * (below ? 0.11 + 0.78 * (1 - t) : 1.11 + 0.78 * t); // 200° to 340°, or 20° to 160°
      final p = o + Offset(math.cos(a) * r, math.sin(a) * r);
      out.add(Offset(
        p.dx.clamp(52.0, math.max(52.0, _size.width - 52)),
        p.dy.clamp(28.0, math.max(28.0, _size.height - 28)),
      ));
    }
    return out;
  }

  int? _hit(Offset p) {
    int? best;
    var bestD = 52.0;
    for (final (i, c) in _centres().indexed) {
      final d = (c - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final on = widget.enabled;
    final arc = _arcAt != null;
    final face = Container(
      width: double.infinity,
      decoration: BoxDecoration(color: on ? c.accent : c.raised, borderRadius: BorderRadius.circular(Radii.large)),
      alignment: Alignment.center,
      child: AnimatedOpacity(
        opacity: arc ? 0.25 : 1,
        duration: Motion.of(context, Motion.pressIn),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RibbonGlyph(color: on ? c.onAccent : c.text2, size: 28),
            const SizedBox(height: Space.m),
            Text('Bookmark', style: text.titleMedium!.copyWith(color: on ? c.onAccent : c.text2)),
            const SizedBox(height: Space.xs),
            Text(
              on && _labels.isNotEmpty ? 'Tap, or hold for a label' : 'Tap anywhere here',
              style: text.bodySmall!.copyWith(color: on ? c.onAccent.withValues(alpha: 0.72) : c.text2),
            ),
          ],
        ),
      ),
    );
    if (!on) return Semantics(button: true, enabled: false, label: 'Bookmark, unavailable', child: ExcludeSemantics(child: face));
    final pressed = _pointer != null;
    return Semantics(
      button: true,
      label: 'Bookmark this moment',
      onTap: widget.onMark,
      customSemanticsActions: {
        for (final l in _labels) CustomSemanticsAction(label: 'Bookmark as $l'): () => _label(l, widget.onMark()),
      },
      child: ExcludeSemantics(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: LayoutBuilder(builder: (context, box) {
            _size = box.biggest;
            return AnimatedScale(
              scale: pressed && !arc ? 0.97 : 1,
              duration: Motion.of(context, Motion.pressIn),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: pressed && !arc ? 0.9 : 1,
                duration: Motion.of(context, Motion.pressIn),
                child: Stack(children: [
                  Positioned.fill(child: face),
                  if (arc)
                    for (final (i, p) in _centres().indexed)
                      Positioned(
                        left: p.dx - 48,
                        top: p.dy - 24,
                        width: 96,
                        height: 48,
                        child: _LabelChip(label: _labels[i], hover: i == _hover),
                      ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label, required this.hover});

  final String label;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AnimatedScale(
      scale: hover ? 1.12 : 1,
      duration: Motion.of(context, Motion.pressIn),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.s),
        decoration: BoxDecoration(
          color: c.onAccent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: hover ? c.bg : c.onAccent, width: 2),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(color: c.accent),
        ),
      ),
    );
  }
}

/// "Mark 3 · 04:32". The newest row is outlined in marigold for 2 s.
class MarkRow extends StatelessWidget {
  const MarkRow({super.key, required this.mark, required this.highlight, this.label});

  final MarkResult mark;
  final bool highlight;

  /// A quick label given while recording; replaces "Mark N".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '${label == null ? '' : '$label, '}Mark ${mark.index} at ${spokenTime(mark.positionMs)}',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.entrance),
          height: kMinTarget,
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.medium),
            border: Border.all(color: highlight ? c.accentInk : c.surface, width: 1.5),
          ),
          child: Row(
            children: [
              RibbonGlyph(color: c.accentInk, size: 14),
              const SizedBox(width: Space.m),
              Expanded(child: Text(label ?? 'Mark ${mark.index}', style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(clock(mark.positionMs), style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56 dp round control with a caption (Pause / Resume / Stop).
class RoundControl extends StatelessWidget {
  const RoundControl({super.key, required this.icon, required this.caption, required this.semanticLabel, required this.onTap, this.iconColor});

  final IconData icon;
  final String caption;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final circle = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.raised, border: Border.all(color: c.border)),
      child: Icon(icon, size: 28, color: onTap == null ? c.text2 : (iconColor ?? c.text)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        onTap == null
            ? Semantics(label: semanticLabel, enabled: false, button: true, child: ExcludeSemantics(child: circle))
            : PressableScale(semanticLabel: semanticLabel, onTap: onTap, child: circle),
        const SizedBox(height: Space.xs),
        ExcludeSemantics(child: Text(caption, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: c.text2))),
      ],
    );
  }
}
