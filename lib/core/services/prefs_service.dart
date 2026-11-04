import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin typed wrapper so features don't scatter string keys.
@lazySingleton
class PrefsService {
  PrefsService(this._prefs);

  final SharedPreferences _prefs;

  static const _themeMode = 'theme_mode';
  static const _defaultFilter = 'default_filter';
  static const _defaultMode = 'default_scan_mode';
  static const _defaultFormat = 'default_export_format';
  static const _defaultPageSize = 'default_page_size';
  static const _flashOn = 'camera_flash_on';
  static const _consentDone = 'ads_consent_done';

  String? get themeMode => _prefs.getString(_themeMode);
  Future<void> setThemeMode(String v) => _prefs.setString(_themeMode, v);

  String? get defaultFilter => _prefs.getString(_defaultFilter);
  Future<void> setDefaultFilter(String v) => _prefs.setString(_defaultFilter, v);

  String? get defaultScanMode => _prefs.getString(_defaultMode);
  Future<void> setDefaultScanMode(String v) => _prefs.setString(_defaultMode, v);

  String? get defaultExportFormat => _prefs.getString(_defaultFormat);
  Future<void> setDefaultExportFormat(String v) =>
      _prefs.setString(_defaultFormat, v);

  String? get defaultPageSize => _prefs.getString(_defaultPageSize);
  Future<void> setDefaultPageSize(String v) =>
      _prefs.setString(_defaultPageSize, v);

  bool get flashOn => _prefs.getBool(_flashOn) ?? false;
  Future<void> setFlashOn(bool v) => _prefs.setBool(_flashOn, v);

  bool get consentDone => _prefs.getBool(_consentDone) ?? false;
  Future<void> setConsentDone(bool v) => _prefs.setBool(_consentDone, v);
}
