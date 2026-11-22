import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin typed wrapper so features don't scatter string keys.
@lazySingleton
class PrefsService {
  PrefsService(this._prefs);

  final SharedPreferences _prefs;

  static const _themeMode = 'theme_mode';
  static const _defaultFilter = 'default_filter';
  static const _defaultFormat = 'default_export_format';
  static const _defaultPageSize = 'default_page_size';
  static const _flashOn = 'camera_flash_on';
  static const _consentDone = 'ads_consent_done';
  static const _shutterSound = 'camera_shutter_sound';
  static const _magneticEdges = 'crop_magnetic_edges';
  static const _defaultQuality = 'default_export_quality';
  static const _signatureInk = 'signature_ink';
  static const _renderVersion = 'page_render_version';
  static const _shareMoreOpen = 'share_more_open';
  static const _exportFooter = 'export_footer';
  static const _photoBackground = 'photo_background';

  String? get themeMode => _prefs.getString(_themeMode);
  Future<void> setThemeMode(String v) => _prefs.setString(_themeMode, v);

  String? get defaultFilter => _prefs.getString(_defaultFilter);
  Future<void> setDefaultFilter(String v) => _prefs.setString(_defaultFilter, v);

  String? get defaultExportFormat => _prefs.getString(_defaultFormat);
  Future<void> setDefaultExportFormat(String v) =>
      _prefs.setString(_defaultFormat, v);

  String? get defaultPageSize => _prefs.getString(_defaultPageSize);
  Future<void> setDefaultPageSize(String v) =>
      _prefs.setString(_defaultPageSize, v);

  /// The page look the documents' cached images were made with.
  int get renderVersion => _prefs.getInt(_renderVersion) ?? 0;
  Future<void> setRenderVersion(int v) => _prefs.setInt(_renderVersion, v);

  bool get flashOn => _prefs.getBool(_flashOn) ?? false;
  Future<void> setFlashOn(bool v) => _prefs.setBool(_flashOn, v);

  bool get magneticEdges => _prefs.getBool(_magneticEdges) ?? true;
  Future<void> setMagneticEdges(bool v) => _prefs.setBool(_magneticEdges, v);

  bool get shutterSound => _prefs.getBool(_shutterSound) ?? true;
  Future<void> setShutterSound(bool v) => _prefs.setBool(_shutterSound, v);

  String? get defaultQuality => _prefs.getString(_defaultQuality);
  Future<void> setDefaultQuality(String v) => _prefs.setString(_defaultQuality, v);

  String? get signatureInk => _prefs.getString(_signatureInk);
  Future<void> setSignatureInk(String v) => _prefs.setString(_signatureInk, v);

  /// The passport photo background last chosen (round 10, P1-7).
  String? get photoBackground => _prefs.getString(_photoBackground);
  Future<void> setPhotoBackground(String v) => _prefs.setString(_photoBackground, v);

  /// "Add Flash Dox footer to pages" (round 10, P1-6): on by default.
  bool get exportFooter => _prefs.getBool(_exportFooter) ?? true;
  Future<void> setExportFooter(bool v) => _prefs.setBool(_exportFooter, v);

  /// Share sheet › More options open (round 10, P1-1).
  bool get shareMoreOpen => _prefs.getBool(_shareMoreOpen) ?? false;
  Future<void> setShareMoreOpen(bool v) => _prefs.setBool(_shareMoreOpen, v);

  /// The format and layout last shared, per scan mode (round 10, P1-2).
  String? lastShareFormat(String mode) => _prefs.getString('share_format_$mode');
  String? lastShareLayout(String mode) => _prefs.getString('share_layout_$mode');
  Future<void> setLastShare(String mode, {required String format, required String layout}) async {
    await _prefs.setString('share_format_$mode', format);
    await _prefs.setString('share_layout_$mode', layout);
  }

  bool get consentDone => _prefs.getBool(_consentDone) ?? false;
  Future<void> setConsentDone(bool v) => _prefs.setBool(_consentDone, v);
}
