import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A row that leaves: it slides left and fades (first half), then its space closes (second half),
/// so the rows below glide up instead of jumping (expensive-mode B7, UI-FEEDBACK-006). Instant with
/// reduced motion. The caller deletes after [leaveTime].
class LeaveOut extends StatelessWidget {
  const LeaveOut({super.key, required this.leaving, required this.child});

  final bool leaving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: leaving ? 1 : 0),
      duration: Motion.of(context, Motion.exit) * 2,
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) {
        final out = (t * 2).clamp(0.0, 1.0);
        final close = ((t - 0.5) * 2).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: leaving, // a row on its way out takes no more taps
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1 - close,
              child: Opacity(
                opacity: 1 - out,
                child: FractionalTranslation(translation: Offset(-0.25 * out, 0), child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How long [LeaveOut] takes here (zero with reduced motion).
Duration leaveTime(BuildContext context) => Motion.of(context, Motion.exit) * 2;
