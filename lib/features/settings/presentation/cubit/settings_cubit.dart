import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.defaultFilter = FilterType.auto,
    this.defaultMode = ScanMode.single,
    this.defaultFormat = ExportFormat.pdf,
    this.defaultPageSize = PdfPageSize.a4,
    this.defaultQuality = ExportQuality.standard,
    this.shutterSound = true,
    this.storageBytes,
    this.version = '',
    this.clearing = false,
  });

  final FilterType defaultFilter;
  final ScanMode defaultMode;
  final ExportFormat defaultFormat;
  final PdfPageSize defaultPageSize;
  final ExportQuality defaultQuality;
  final bool shutterSound;
  final int? storageBytes;
  final String version;
  final bool clearing;

  SettingsState copyWith({
    FilterType? defaultFilter,
    ScanMode? defaultMode,
    ExportFormat? defaultFormat,
    PdfPageSize? defaultPageSize,
    ExportQuality? defaultQuality,
    bool? shutterSound,
    int? storageBytes,
    String? version,
    bool? clearing,
  }) =>
      SettingsState(
        defaultFilter: defaultFilter ?? this.defaultFilter,
        defaultMode: defaultMode ?? this.defaultMode,
        defaultFormat: defaultFormat ?? this.defaultFormat,
        defaultPageSize: defaultPageSize ?? this.defaultPageSize,
        defaultQuality: defaultQuality ?? this.defaultQuality,
        shutterSound: shutterSound ?? this.shutterSound,
        storageBytes: storageBytes ?? this.storageBytes,
        version: version ?? this.version,
        clearing: clearing ?? this.clearing,
      );

  @override
  List<Object?> get props =>
      [defaultFilter, defaultMode, defaultFormat, defaultPageSize, defaultQuality, shutterSound, storageBytes, version, clearing];
}

@injectable
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs, this._files, this._storage) : super(_read(_prefs)) {
    unawaited(refreshStorage());
    unawaited(_loadVersion());
  }

  final PrefsService _prefs;
  final FileStore _files;
  final GetStorageUsed _storage;

  static T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  static SettingsState _read(PrefsService p) => SettingsState(
        defaultFilter: _enum(FilterType.values, p.defaultFilter, FilterType.auto),
        defaultMode: _enum(ScanMode.values, p.defaultScanMode, ScanMode.single),
        defaultFormat: _enum(ExportFormat.values, p.defaultExportFormat, ExportFormat.pdf),
        defaultPageSize: _enum(PdfPageSize.values, p.defaultPageSize, PdfPageSize.a4),
        defaultQuality: _enum(ExportQuality.values, p.defaultQuality, ExportQuality.standard),
        shutterSound: p.shutterSound,
      );

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      emit(state.copyWith(version: '${info.version} (${info.buildNumber})'));
    } catch (_) {}
  }

  Future<void> refreshStorage() async {
    final r = await _storage();
    emit(state.copyWith(storageBytes: r.getOrElse((_) => 0)));
  }

  Future<void> setDefaultFilter(FilterType f) async {
    emit(state.copyWith(defaultFilter: f));
    await _prefs.setDefaultFilter(f.name);
  }

  Future<void> setDefaultMode(ScanMode m) async {
    emit(state.copyWith(defaultMode: m));
    await _prefs.setDefaultScanMode(m.name);
  }

  Future<void> setDefaultFormat(ExportFormat f) async {
    emit(state.copyWith(defaultFormat: f));
    await _prefs.setDefaultExportFormat(f.name);
  }

  Future<void> setDefaultPageSize(PdfPageSize s) async {
    emit(state.copyWith(defaultPageSize: s));
    await _prefs.setDefaultPageSize(s.name);
  }

  Future<void> setDefaultQuality(ExportQuality q) async {
    emit(state.copyWith(defaultQuality: q));
    await _prefs.setDefaultQuality(q.name);
  }

  Future<void> setShutterSound(bool on) async {
    emit(state.copyWith(shutterSound: on));
    await _prefs.setShutterSound(on);
  }

  Future<void> clearTemp() async {
    emit(state.copyWith(clearing: true));
    try {
      await _files.clearCaches();
    } finally {
      emit(state.copyWith(clearing: false));
      await refreshStorage();
    }
  }
}
