import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../password_tools.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Text styles. Colours come from the theme, so these only set size and weight.
// ---------------------------------------------------------------------------

class AppText {
  static const TextStyle display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.1,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(fontSize: 14, height: 1.4);
  static const TextStyle caption = TextStyle(fontSize: 12.5, height: 1.3);
  static const TextStyle overline = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
  );
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/// A light tap vibration. Never throws, even where vibration is missing.
void tapFeedback() {
  HapticFeedback.selectionClick().catchError((Object _) {});
}

/// A fade between two screens (used when the app locks or unlocks).
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
  );
}

Color strengthColor(Palette p, StrengthLevel level) {
  switch (level) {
    case StrengthLevel.veryWeak:
      return p.danger;
    case StrengthLevel.weak:
      return const Color(0xFFFF8A3D);
    case StrengthLevel.fair:
      return p.warning;
    case StrengthLevel.strong:
      return p.success;
    case StrengthLevel.veryStrong:
      return p.accent;
  }
}

// ---------------------------------------------------------------------------
// Toast, confirm dialog, sheets
// ---------------------------------------------------------------------------

enum ToastKind { info, success, warning, error }

/// The look of every message at the bottom of the screen.
SnackBar buildToast(
  Palette p,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final Color color;
  final IconData icon;
  switch (kind) {
    case ToastKind.success:
      color = p.success;
      icon = Icons.check_circle_rounded;
    case ToastKind.warning:
      color = p.warning;
      icon = Icons.warning_amber_rounded;
    case ToastKind.error:
      color = p.danger;
      icon = Icons.error_rounded;
    case ToastKind.info:
      color = p.primary;
      icon = Icons.info_rounded;
  }

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: p.surfaceAlt,
    elevation: 0,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: color.withAlpha(110)),
    ),
    action: (actionLabel != null && onAction != null)
        ? SnackBarAction(
            label: actionLabel,
            textColor: p.primary,
            onPressed: onAction,
          )
        : null,
    content: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: TextStyle(color: p.text, fontSize: 14)),
        ),
      ],
    ),
  );
}

void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    buildToast(
      Palette.of(context),
      message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final p = Palette.of(context);
  final accent = destructive ? p.danger : p.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.border),
      ),
      icon: Icon(icon, color: accent, size: 32),
      title: Text(title, textAlign: TextAlign.center, style: AppText.title),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: AppText.body.copyWith(color: p.muted),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('Cancel', style: TextStyle(color: p.muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final p = Palette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}

class Choice<T> {
  final T value;
  final String label;
  final String? subtitle;
  const Choice(this.value, this.label, [this.subtitle]);
}

/// A bottom sheet that lets the user pick one option.
Future<T?> pickChoice<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  required T selected,
}) {
  return showAppSheet<T>(
    context,
    builder: (sheetContext) {
      final p = Palette.of(sheetContext);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.title),
            const SizedBox(height: 8),
            for (final choice in choices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  choice.label,
                  style: TextStyle(
                    fontWeight: choice.value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                subtitle: choice.subtitle == null
                    ? null
                    : Text(
                        choice.subtitle!,
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                trailing: choice.value == selected
                    ? Icon(Icons.check_circle_rounded, color: p.primary)
                    : Icon(Icons.circle_outlined, color: p.border),
                onTap: () => Navigator.pop(sheetContext, choice.value),
              ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Brand and layout pieces
// ---------------------------------------------------------------------------

/// The KeyMaster logo: a gradient tile with a key and a soft glow.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: p.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: p.primary.withAlpha(105),
            blurRadius: size * 0.5,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Icon(Icons.key_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Two soft colour glows behind a screen, for the lock and welcome screens.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  Widget _glow(Palette p, Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withAlpha(p.isDark ? 72 : 46),
              color.withAlpha(0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: p.bg)),
        Positioned(top: -130, left: -90, child: _glow(p, p.primary, 380)),
        Positioned(bottom: -150, right: -110, child: _glow(p, p.accent, 400)),
        // A transparent Material on top of the background, so button ripples
        // are drawn above it and not hidden underneath.
        Positioned.fill(
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ],
    );
  }
}

/// A round icon button with a thin border, for screen headers.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final button = Material(
      color: p.surface,
      shape: CircleBorder(side: BorderSide(color: p.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed == null
            ? null
            : () {
                tapFeedback();
                onPressed!();
              },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 21, color: color ?? p.text),
        ),
      ),
    );
    final label = tooltip;
    return label == null ? button : Tooltip(message: label, child: button);
  }
}

/// A password drawn in a fixed-width font, with digits and symbols in colour
/// so they are easy to tell apart (0 and O, l and 1).
class ColoredPassword extends StatelessWidget {
  final String password;
  final double fontSize;
  final TextAlign textAlign;

  const ColoredPassword({
    super.key,
    required this.password,
    this.fontSize = 17,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Color colorOf(String ch) {
      if (RegExp(r'[0-9]').hasMatch(ch)) return p.primary;
      if (RegExp(r'[A-Za-z]').hasMatch(ch)) return p.text;
      return p.accent;
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          height: 1.35,
        ),
        children: [
          for (final rune in password.runes)
            TextSpan(
              text: String.fromCharCode(rune),
              style: TextStyle(color: colorOf(String.fromCharCode(rune))),
            ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.gradient,
    this.color,
    this.borderColor,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final shape = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? p.surface) : null,
          gradient: gradient,
          borderRadius: shape,
          border: Border.all(color: borderColor ?? p.border),
        ),
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The big title at the top of a tab.
class PageTitle extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final Widget? trailing;

  const PageTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    eyebrow!.toUpperCase(),
                    style: AppText.overline.copyWith(color: p.muted),
                  ),
                ),
              Text(title, style: AppText.display),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: AppText.overline.copyWith(color: p.muted),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// A round-cornered tile with the first letter of the title (or a note icon).
/// The colour comes from the title, so the same service is always the same
/// colour.
class ItemAvatar extends StatelessWidget {
  final String title;
  final bool isNote;
  final double size;

  const ItemAvatar({
    super.key,
    required this.title,
    this.isNote = false,
    this.size = 46,
  });

  static Color colorFor(String title, Palette p) {
    final colors = <Color>[
      p.primary,
      p.accent,
      p.violet,
      p.warning,
      p.success,
      p.danger,
      const Color(0xFFFF7AC6),
    ];
    var hash = 0;
    for (final unit in title.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }

  String get _letter {
    for (final rune in title.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = isNote ? p.violet : colorFor(title, p);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: isNote
          ? Icon(Icons.sticky_note_2_rounded, color: color, size: size * 0.48)
          : Text(
              _letter,
              style: TextStyle(
                color: color,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = color ?? p.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [tint.withAlpha(60), tint.withAlpha(0)],
                    ),
                  ),
                ),
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withAlpha(34),
                    border: Border.all(color: tint.withAlpha(90)),
                  ),
                  child: Icon(icon, color: tint, size: 38),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: AppText.title),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: p.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              GradientButton(
                label: actionLabel!,
                icon: Icons.add_rounded,
                expanded: false,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tinted note with an icon, for tips and warnings.
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = color ?? p.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppText.caption.copyWith(color: p.text)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons, fields, chips
// ---------------------------------------------------------------------------

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final bool danger;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onPressed != null && !loading;
    final Gradient gradient = danger
        ? LinearGradient(colors: [p.danger, const Color(0xFFFF8A5C)])
        : p.brandGradient;
    final glow = danger ? p.danger : p.primary;
    final radius = BorderRadius.circular(16);

    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: glow.withAlpha(enabled ? 70 : 0),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
            child: InkWell(
              borderRadius: radius,
              onTap: enabled ? onPressed : null,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    else ...[
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet button with a tinted background.
class SoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  const SoftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = color ?? p.primary;
    final radius = BorderRadius.circular(14);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: tint.withAlpha(30),
            borderRadius: radius,
            border: Border.all(color: tint.withAlpha(80)),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: tint, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool obscure;
  final bool secret; // turns off suggestions and autocorrect
  final Widget? suffix;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autofocus;

  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.obscure = false,
    this.secret = false,
    this.suffix,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: obscure ? 1 : maxLines,
      minLines: obscure ? 1 : minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofocus: autofocus,
      autocorrect: !secret,
      enableSuggestions: !secret,
      cursorColor: p.primary,
      style: TextStyle(color: p.text, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: p.muted),
        floatingLabelStyle: TextStyle(color: p.primary),
        hintStyle: TextStyle(color: p.muted.withAlpha(150)),
        prefixIcon: icon == null ? null : Icon(icon, color: p.muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: p.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(p.primary, 1.6),
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = selected ? p.onPrimary : p.muted;
    return Material(
      color: selected ? p.primary : p.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? p.primary : p.border),
      ),
      animationDuration: const Duration(milliseconds: 180),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          tapFeedback();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: fg.withAlpha(selected ? 220 : 170),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Five bars that fill and change colour with the password strength.
class StrengthMeter extends StatelessWidget {
  final StrengthLevel level;
  final bool empty;
  final String? label;

  const StrengthMeter({
    super.key,
    required this.level,
    this.empty = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = strengthColor(p, level);
    final filled = empty ? 0 : level.index + 1;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 6,
                    margin: EdgeInsets.only(right: i == 4 ? 0 : 5),
                    decoration: BoxDecoration(
                      color: i < filled ? color : p.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 12),
          Text(
            label!,
            style: TextStyle(
              color: empty ? p.muted : color,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings rows
// ---------------------------------------------------------------------------

class SettingTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = danger ? p.danger : (color ?? p.primary);
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              tapFeedback();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconBadge(icon: icon, color: tint, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: danger ? p.danger : p.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppText.caption.copyWith(color: p.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

/// Rows grouped in one rounded card with thin dividers between them.
class SettingGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 70, color: p.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrance animation
// ---------------------------------------------------------------------------

/// Fades and slides its child in once, when it first appears. [index] staggers
/// the start so lists cascade instead of popping in together.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final delay = math.min(widget.index, 8) * 45;
    final total = 380 + delay;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    )..forward();
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
