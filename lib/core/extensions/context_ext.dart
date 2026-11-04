import 'package:flash_dox/app/theme/app_colors.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';

extension BuildContextX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  AppLocalizations get l10n => AppLocalizations.of(this);
  bool get isDark => colors.isDark;
  Size get screen => MediaQuery.sizeOf(this);
  EdgeInsets get padding => MediaQuery.paddingOf(this);

  void showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Dark mode's danger red is light, so it takes dark text.
          content: Text(
            message,
            style: error
                ? text.bodyMedium?.copyWith(color: colors.isDark ? const Color(0xFF2A0A0A) : Colors.white)
                : null,
          ),
          backgroundColor: error ? colors.danger : null,
        ),
      );
  }
}
