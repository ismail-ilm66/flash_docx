import 'dart:async';

import 'package:flash_dox/core/services/night_mode_service.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._prefs, this._nightMode) : super(_read(_prefs)) {
    // Re-sync on every start: the OS keeps the value, but a reinstall or a
    // restored backup can leave it out of step with prefs.
    unawaited(_nightMode.apply(state));
  }

  final PrefsService _prefs;
  final NightModeService _nightMode;

  static ThemeMode _read(PrefsService p) => switch (p.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> set(ThemeMode mode) async {
    emit(mode);
    await _prefs.setThemeMode(mode.name);
    await _nightMode.apply(mode);
  }
}
