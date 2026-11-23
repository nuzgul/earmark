import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Press feedback that starts on touch-down (UI-MOTION-001, expensive-mode A1):
/// sinks and darkens while held, returns without overshoot on release or cancel.
/// [onPressDown] fires on touch-down for actions that must not wait for release
/// (a bookmark); [onTap] fires on release like a normal button.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.onPressDown,
    this.pressedScale = 0.97,
    this.haptic = false,
  });

  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onPressDown;
  final double pressedScale;

  /// Haptic on the same frame as the visual change; only for moments that matter.
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.pressIn);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onTap ?? widget.onPressDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _set(true);
          if (widget.haptic) HapticFeedback.mediumImpact();
          widget.onPressDown?.call();
        },
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.9 : 1,
            duration: duration,
            child: ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
    );
  }
}
