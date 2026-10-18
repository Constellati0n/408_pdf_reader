import 'package:flutter/material.dart';

/// Brand palette taken from the original 408真题系统 logo.
const Color kBrandTeal = Color(0xFF00BAAD);
const Color kBrandGreen = Color(0xFF43CF7C);

/// Tuned light/dark themes seeded from the brand teal.
ThemeData buildAppTheme(Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kBrandTeal,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
  );
}
