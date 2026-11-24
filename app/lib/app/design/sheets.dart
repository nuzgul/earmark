import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pressable_scale.dart';
import 'tokens.dart';

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) build) {
  final c = AppColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large))),
    // Scrolls when the content does not fit: large text, or landscape with the keyboard up.
    builder: (ctx) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl + MediaQuery.viewInsetsOf(ctx).bottom),
      child: build(ctx),
    ),
  );
}

/// Opens any sheet with the app's sheet styling.
Future<T?> showAppSheet<T>(BuildContext context, Widget Function(BuildContext) build) => _sheet(context, build);

/// Full-width pill button used in sheets.
class SheetButton extends StatelessWidget {
  const SheetButton({super.key, required this.label, required this.onTap, this.fill, this.ink});

  final String label;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final child = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill ?? c.raised, borderRadius: BorderRadius.circular(100)),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: onTap == null ? c.text2 : (ink ?? c.text))),
    );
    if (onTap == null) return Semantics(button: true, enabled: false, label: label, child: ExcludeSemantics(child: child));
    return PressableScale(semanticLabel: label, onTap: onTap, child: child);
  }
}

/// Rename sheet; returns the new text, or null when dismissed.
Future<String?> askText(BuildContext context, {required String title, required String initial, String hint = ''}) {
  final controller = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final done = _sheet<String>(context, (ctx) {
    final c = AppColors.of(ctx);
    final text = Theme.of(ctx).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: Space.l),
        TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: text.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: c.raised,
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.small), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        const SizedBox(height: Space.l),
        SheetButton(label: 'Save', fill: c.text, ink: c.bg, onTap: () => Navigator.pop(ctx, controller.text)),
      ],
    );
  });
  return done.whenComplete(controller.dispose);
}

/// Yes/no sheet for permanent actions; true only on an explicit tap of [action].
Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await _sheet<bool>(context, (ctx) {
    final c = AppColors.of(ctx);
    final text = Theme.of(ctx).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: Space.s),
        Text(message, style: text.bodyLarge!.copyWith(color: c.text2)),
        const SizedBox(height: Space.xl),
        SheetButton(label: action, ink: c.rec, onTap: () => Navigator.pop(ctx, true)),
        const SizedBox(height: Space.s),
        SheetButton(label: 'Cancel', fill: c.surface, onTap: () => Navigator.pop(ctx, false)),
      ],
    );
  });
  return ok ?? false;
}

/// Where a finger last went down (global). Menus open from there, so they grow out of the control
/// that asked for them and shrink back into it (expensive-mode B1). Started once at app start.
Offset? lastTouch;
bool _tracking = false;

void trackLastTouch() {
  if (_tracking) return;
  _tracking = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
    if (e is PointerDownEvent) lastTouch = e.position;
  });
}

/// A short list of actions (rename, delete…): a menu at the control that opened it, or a bottom
/// sheet when no touch is known or a screen reader drives the app (its double tap is no touch,
/// so the last finger position would be stale).
Future<T?> chooseAction<T>(BuildContext context, List<({String label, T value, bool danger})> actions) {
  final at = lastTouch;
  if (at == null || MediaQuery.accessibleNavigationOf(context)) return _actionSheet(context, actions);
  final c = AppColors.of(context);
  final text = Theme.of(context).textTheme;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final p = overlay.globalToLocal(at);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(Rect.fromCenter(center: p, width: 1, height: 1), Offset.zero & overlay.size),
    color: c.raised,
    elevation: 0, // a hairline instead of a shadow
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium), side: BorderSide(color: c.border)),
    constraints: const BoxConstraints(minWidth: 200),
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
    items: [
      for (final a in actions)
        PopupMenuItem<T>(
          value: a.value,
          height: 52,
          child: Text(a.label, style: text.labelLarge!.copyWith(color: a.danger ? c.rec : c.text)),
        ),
    ],
  );
}

Future<T?> _actionSheet<T>(BuildContext context, List<({String label, T value, bool danger})> actions) {
  return _sheet<T>(context, (ctx) {
    final c = AppColors.of(ctx);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions) ...[
          SheetButton(label: a.label, ink: a.danger ? c.rec : null, onTap: () => Navigator.pop(ctx, a.value)),
          const SizedBox(height: Space.s),
        ],
      ],
    );
  });
}

/// 48 dp round icon button (top bars, row menus).
class IconTap extends StatelessWidget {
  const IconTap({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => PressableScale(
        semanticLabel: label,
        onTap: onTap,
        child: SizedBox.square(dimension: kMinTarget, child: Icon(icon, color: color ?? AppColors.of(context).text)),
      );
}
