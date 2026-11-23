// Design tokens from docs/ui-premium/PLAN.md. Contrast ratios there are measured from these values.
import 'package:flutter/material.dart';

/// Colour roles. Marigold (accent) is for marks only; rec is for live capture only.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.text,
    required this.text2,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.accentInk,
    required this.rec,
    required this.success,
  });

  final Color bg, surface, raised, text, text2, border;

  /// Marigold fill: Bookmark zone, ribbon flags, mark badges.
  final Color accent;
  final Color onAccent;

  /// Marigold used as text, icon or the ring around an accent fill on light backgrounds.
  final Color accentInk;
  final Color rec, success;

  static const dark = AppColors(
    bg: Color(0xFF14130F),
    surface: Color(0xFF1E1C17),
    raised: Color(0xFF29261F),
    text: Color(0xFFF3EEE2),
    text2: Color(0xFFADA593),
    border: Color(0xFF77705E),
    accent: Color(0xFFFFC23D),
    onAccent: Color(0xFF1A1405),
    accentInk: Color(0xFFFFC23D),
    rec: Color(0xFFFF6B5E),
    success: Color(0xFF63D69C),
  );

  static const light = AppColors(
    bg: Color(0xFFF7F3EA),
    surface: Color(0xFFEFE9DC),
    raised: Color(0xFFFBF8F1),
    text: Color(0xFF1B1812),
    text2: Color(0xFF5C5547),
    border: Color(0xFF8C8472),
    accent: Color(0xFFFFC23D),
    onAccent: Color(0xFF1A1405),
    accentInk: Color(0xFF7A5500),
    rec: Color(0xFFB02E22),
    success: Color(0xFF1B6B43),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      border: l(border, other.border),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentInk: l(accentInk, other.accentInk),
      rec: l(rec, other.rec),
      success: l(success, other.success),
    );
  }
}

abstract final class Space {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 20, xxl = 28, xxxl = 40;

  /// Side padding of every screen.
  static const double screen = 20;
}

abstract final class Radii {
  static const double large = 28, medium = 18, small = 10;
}

/// Durations by role (UI-MOTION-023). Exits are faster than entrances.
abstract final class Motion {
  static const pressIn = Duration(milliseconds: 90);
  static const entrance = Duration(milliseconds: 250);
  static const exit = Duration(milliseconds: 160);
  static const countRoll = Duration(milliseconds: 200);
  static const staggerStep = Duration(milliseconds: 50);

  /// Reduced motion: an instant change or a short fade.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// Minimum touch target (48 dp on Android, above 44 pt on iOS).
const double kMinTarget = 48;
