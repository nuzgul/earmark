import 'package:flutter/material.dart';

import 'tokens.dart';

const _family = 'MonaSans';

/// One style per size step (13/16/20/25/32, timer 76). The variable font gets its
/// weight through FontVariation, because FontWeight alone does not drive the wght axis.
TextStyle _style(double size, double weight, double height, {double tracking = 0, bool tabular = false}) =>
    TextStyle(
      fontFamily: _family,
      fontSize: size,
      height: height,
      letterSpacing: tracking * size,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: [FontVariation.weight(weight)],
      // Mona Sans' tabular zero is slashed (instrument-readout look); ss08 is a barred zero, not plain.
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

TextTheme _textTheme(Color text, Color text2) {
  final base = TextTheme(
    displayLarge: _style(76, 600, 1.0, tracking: -0.04, tabular: true), // recording timer
    displaySmall: _style(56, 600, 1.0, tracking: -0.04, tabular: true), // timer in landscape
    headlineLarge: _style(32, 650, 1.1, tracking: -0.03),
    headlineSmall: _style(25, 650, 1.15, tracking: -0.02),
    titleMedium: _style(20, 600, 1.2, tracking: -0.01),
    bodyLarge: _style(16, 450, 1.5),
    bodyMedium: _style(16, 450, 1.5),
    bodySmall: _style(13, 450, 1.4),
    labelLarge: _style(16, 600, 1.2),
    labelMedium: _style(13, 600, 1.3, tracking: 0.01),
    labelSmall: _style(12, 600, 1.3, tracking: 0.08),
  );
  return base
      .apply(bodyColor: text, displayColor: text)
      .copyWith(bodySmall: base.bodySmall!.copyWith(color: text2));
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.text,
    onSecondary: c.bg,
    error: c.rec,
    onError: c.bg,
    surface: c.bg,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.raised,
    outline: c.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: _family,
    textTheme: _textTheme(c.text, c.text2),
    extensions: [c],
    splashFactory: NoSplash.splashFactory, // press feedback comes from PressableScale
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.raised,
      contentTextStyle: _style(16, 450, 1.4).copyWith(color: c.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
    ),
  );
}
