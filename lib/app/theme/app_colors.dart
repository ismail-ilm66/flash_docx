import 'package:flutter/material.dart';

/// Design tokens from the "Flash Dox App Design" canvas. Widgets read colours
/// from `context.colors` and never hard-code them.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderStrong,
    required this.stage,
    required this.chip,
    required this.scrim,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentSoft,
    required this.danger,
    required this.success,
    required this.isDark,
  });

  static const Color amber = Color(0xFFFFC233);
  static const Color onAmber = Color(0xFF1B1400);

  static const AppColors dark = AppColors(
    bg: Color(0xFF0F1012),
    surface: Color(0xFF1A1C20),
    surface2: Color(0xFF24272D),
    border: Color(0xFF2E3239),
    borderStrong: Color(0xFF3A3E46),
    stage: Color(0xFF1A1C20),
    chip: Color(0xFF2E3239),
    scrim: Color(0x9E000000), // 62%
    text: Color(0xFFF3F3F1),
    muted: Color(0xFFA6AAB2),
    accent: amber,
    onAccent: onAmber,
    accentText: amber,
    accentSoft: Color(0x24FFC233), // 14%
    danger: Color(0xFFFF8A8A),
    success: Color(0xFF4CD37B),
    isDark: true,
  );

  static const AppColors light = AppColors(
    bg: Color(0xFFF5F5F2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEEEEA),
    border: Color(0xFFE1E1DC),
    borderStrong: Color(0xFFD6D6D0),
    stage: Color(0xFFE8E8E3),
    chip: Color(0xFFFFFFFF),
    scrim: Color(0x730F1012), // 45%
    text: Color(0xFF15171A),
    muted: Color(0xFF5C6169),
    accent: amber,
    onAccent: onAmber,
    accentText: Color(0xFF8A5A00),
    accentSoft: Color(0x38FFC233), // 22%
    danger: Color(0xFFD83A3A),
    success: Color(0xFF1F9D55),
    isDark: false,
  );

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;

  /// Outline for controls (chips, outlined buttons, inputs on sheets).
  final Color borderStrong;

  /// Backdrop behind a page preview (viewer, print layout).
  final Color stage;

  /// Small counters and badges on [stage].
  final Color chip;

  /// Modal barrier behind sheets and dialogs.
  final Color scrim;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color accentSoft;
  final Color danger;
  final Color success;
  final bool isDark;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? borderStrong,
    Color? stage,
    Color? chip,
    Color? scrim,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? accentSoft,
    Color? danger,
    Color? success,
    bool? isDark,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      stage: stage ?? this.stage,
      chip: chip ?? this.chip,
      scrim: scrim ?? this.scrim,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      accentSoft: accentSoft ?? this.accentSoft,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
