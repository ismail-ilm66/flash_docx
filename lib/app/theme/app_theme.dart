import 'package:flash_dox/app/theme/app_colors.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppTheme {
  static const String fontFamily = 'Manrope';

  static ThemeData get dark => _build(AppColors.dark);
  static ThemeData get light => _build(AppColors.light);

  static ThemeData _build(AppColors c) {
    final brightness = c.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentText,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.text,
      surfaceContainerHighest: c.surface2,
      outline: c.border,
      onSurfaceVariant: c.muted,
    );

    final text = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.surface,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: c.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      iconTheme: IconThemeData(color: c.text, size: Sizes.icon),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: Radii.xlR),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.isDark ? c.surface2 : c.text,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: c.isDark ? c.text : c.bg,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.mdR),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        hintStyle: text.bodyMedium?.copyWith(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        border: OutlineInputBorder(
          borderRadius: Radii.mdR,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.mdR,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.mdR,
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.border,
        thumbColor: c.accent,
        overlayColor: c.accentSoft,
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surface2,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.border),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.text,
        textColor: c.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accentSoft,
        selectionHandleColor: c.accent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.border,
        circularTrackColor: c.border,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(AppColors c) {
    TextStyle s(double size, FontWeight w, {double? height, double? ls}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: w,
          color: c.text,
          height: height ?? 1.3,
          letterSpacing: ls,
        );
    return TextTheme(
      displayLarge: s(40, FontWeight.w800, height: 1.1, ls: -0.5),
      displayMedium: s(32, FontWeight.w800, height: 1.15, ls: -0.5),
      headlineLarge: s(28, FontWeight.w700, height: 1.2),
      headlineMedium: s(24, FontWeight.w700, height: 1.2),
      headlineSmall: s(20, FontWeight.w700),
      titleLarge: s(18, FontWeight.w700),
      titleMedium: s(16, FontWeight.w600),
      titleSmall: s(14, FontWeight.w600),
      bodyLarge: s(16, FontWeight.w500),
      bodyMedium: s(14, FontWeight.w500),
      bodySmall: s(12, FontWeight.w500),
      labelLarge: s(14, FontWeight.w700),
      labelMedium: s(12, FontWeight.w600),
      labelSmall: s(11, FontWeight.w600, ls: 0.2),
    );
  }
}
