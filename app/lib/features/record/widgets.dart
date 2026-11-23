import 'package:flutter/material.dart';

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
      builder: (context, v, _) => FractionallySizedBox(
        widthFactor: v,
        child: DecoratedBox(
          decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
          child: const SizedBox(height: 4),
        ),
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

/// The big marigold target. Marks on touch-down, not release.
class BookmarkZone extends StatelessWidget {
  const BookmarkZone({super.key, required this.onMark, required this.enabled});

  final VoidCallback onMark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final zone = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: enabled ? c.accent : c.raised,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RibbonGlyph(color: enabled ? c.onAccent : c.text2, size: 28),
          const SizedBox(height: Space.m),
          Text('Bookmark', style: text.titleMedium!.copyWith(color: enabled ? c.onAccent : c.text2)),
          const SizedBox(height: Space.xs),
          Text(
            'Tap anywhere here',
            style: text.bodySmall!.copyWith(color: enabled ? c.onAccent.withValues(alpha: 0.72) : c.text2),
          ),
        ],
      ),
    );
    if (!enabled) return Semantics(label: 'Bookmark, unavailable', child: ExcludeSemantics(child: zone));
    return PressableScale(semanticLabel: 'Bookmark this moment', haptic: true, onPressDown: onMark, child: zone);
  }
}

/// "Mark 3 · 04:32". The newest row is outlined in marigold for 2 s.
class MarkRow extends StatelessWidget {
  const MarkRow({super.key, required this.mark, required this.highlight});

  final MarkResult mark;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Mark ${mark.index} at ${spokenTime(mark.positionMs)}',
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
              Expanded(child: Text('Mark ${mark.index}', style: text.bodyLarge)),
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
