import 'package:flutter/material.dart';

/// Every colour the app uses, in one place. Screens read it with
/// `Palette.of(context)`, so light and dark mode need no extra code.
class Palette {
  final Brightness brightness;
  final Color bg; // screen background
  final Color surface; // cards
  final Color surfaceAlt; // inputs and raised areas inside cards
  final Color border;
  final Color text;
  final Color muted; // secondary text
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color violet;
  final Color danger;
  final Color warning;
  final Color success;

  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.violet,
    required this.danger,
    required this.warning,
    required this.success,
  });

  static const Palette dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A1020),
    surface: Color(0xFF121A2E),
    surfaceAlt: Color(0xFF1A2540),
    border: Color(0xFF263252),
    text: Color(0xFFEAF0FF),
    muted: Color(0xFF93A2C4),
    primary: Color(0xFF4C8DFF),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF22D3C5),
    violet: Color(0xFFA27BFF),
    danger: Color(0xFFFF5D7A),
    warning: Color(0xFFFFB547),
    success: Color(0xFF34D399),
  );

  static const Palette light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F6FC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE9EFFA),
    border: Color(0xFFD7E0F0),
    text: Color(0xFF0C1630),
    muted: Color(0xFF5A6A8E),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF0FA89B),
    violet: Color(0xFF7C4DFF),
    danger: Color(0xFFE5365A),
    warning: Color(0xFFD98200),
    success: Color(0xFF0E9F6E),
  );

  bool get isDark => brightness == Brightness.dark;

  /// The blue-to-teal gradient used for the logo, buttons and highlights.
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, accent],
      );

  static Palette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

/// Builds the Flutter theme from a [Palette].
///
/// Only widgets that are stable across Flutter versions are themed here.
/// Cards, inputs, dialogs and snack bars get their look from the shared
/// widgets in widgets.dart instead.
class AppTheme {
  static ThemeData get dark => _build(Palette.dark);
  static ThemeData get light => _build(Palette.light);

  static ThemeData _build(Palette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.accent,
      onSecondary: const Color(0xFF031A18),
      error: p.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
      surfaceContainerHighest: p.surfaceAlt,
      outline: p.border,
      outlineVariant: p.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primary.withAlpha(42),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.primary : p.muted,
          );
        }),
      ),
    );
  }
}
