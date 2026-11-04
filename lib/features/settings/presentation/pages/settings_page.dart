import 'dart:io';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/constants/app_info.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:flash_dox/features/settings/presentation/cubit/theme_cubit.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _bytes(int? b) {
    if (b == null) return '…';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _pageSize(BuildContext context, PdfPageSize p) {
    final l = context.l10n;
    return switch (p) {
      PdfPageSize.a4 => l.sharePageA4,
      PdfPageSize.letter => l.sharePageLetter,
      PdfPageSize.fit => l.sharePageFit,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final storeUrl = Platform.isIOS ? AppInfo.appStoreUrl : AppInfo.playStoreUrl;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, s) {
        final cubit = context.read<SettingsCubit>();
        final format = s.defaultFormat == ExportFormat.png ? ExportFormat.jpg : s.defaultFormat;
        return AppScaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x6),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x1, Space.x5, Space.x1, Space.x4),
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.settingsTitle,
                      style: context.text.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                _Section(
                  title: l.settingsAppearance,
                  child: BlocBuilder<ThemeCubit, ThemeMode>(
                    builder: (context, mode) => SegmentedPills<ThemeMode>(
                      accent: true,
                      height: 44,
                      values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                      selected: mode,
                      labelOf: (m) => switch (m) {
                        ThemeMode.system => l.settingsThemeSystem,
                        ThemeMode.light => l.settingsThemeLight,
                        ThemeMode.dark => l.settingsThemeDark,
                      },
                      onChanged: context.read<ThemeCubit>().set,
                    ),
                  ),
                ),
                _Section(
                  title: l.settingsScan,
                  child: _Group(
                    rows: [
                      _Row(
                        label: l.settingsDefaultFilter,
                        value: filterLabel(context, s.defaultFilter),
                        onTap: () async {
                          final v = await showChoiceSheet<FilterType>(
                            context,
                            title: l.settingsDefaultFilter,
                            values: FilterType.values,
                            selected: s.defaultFilter,
                            labelOf: (f) => filterLabel(context, f),
                          );
                          if (v != null) await cubit.setDefaultFilter(v);
                        },
                      ),
                      _Row(
                        label: l.settingsDefaultMode,
                        value: modeLabel(context, s.defaultMode),
                        onTap: () async {
                          final v = await showChoiceSheet<ScanMode>(
                            context,
                            title: l.settingsDefaultMode,
                            values: ScanMode.values,
                            selected: s.defaultMode,
                            labelOf: (m) => modeLabel(context, m),
                          );
                          if (v != null) await cubit.setDefaultMode(v);
                        },
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: l.settingsShare,
                  child: _Group(
                    rows: [
                      _Row(
                        label: l.settingsDefaultFormat,
                        value: format == ExportFormat.pdf ? l.sharePdf : l.shareJpg,
                        onTap: () async {
                          final v = await showChoiceSheet<ExportFormat>(
                            context,
                            title: l.settingsDefaultFormat,
                            values: const [ExportFormat.pdf, ExportFormat.jpg],
                            selected: format,
                            labelOf: (f) => f == ExportFormat.pdf ? l.sharePdf : l.shareJpg,
                          );
                          if (v != null) await cubit.setDefaultFormat(v);
                        },
                      ),
                      _Row(
                        label: l.settingsDefaultPageSize,
                        value: _pageSize(context, s.defaultPageSize),
                        onTap: () async {
                          final v = await showChoiceSheet<PdfPageSize>(
                            context,
                            title: l.settingsDefaultPageSize,
                            values: PdfPageSize.values,
                            selected: s.defaultPageSize,
                            labelOf: (p) => _pageSize(context, p),
                          );
                          if (v != null) await cubit.setDefaultPageSize(v);
                        },
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: l.settingsStorage,
                  child: _Group(
                    rows: [
                      _Row(label: l.settingsStorageUsed, value: _bytes(s.storageBytes)),
                      _Row(
                        label: l.settingsClearTemp,
                        trailing: s.clearing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                        onTap: s.clearing
                            ? null
                            : () async {
                                await cubit.clearTemp();
                                if (context.mounted) context.showSnack(l.settingsClearedTemp);
                              },
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: l.settingsAbout,
                  child: _Group(
                    rows: [
                      _Row(label: l.settingsPrivacy, onTap: () => _open(AppInfo.privacyPolicyUrl)),
                      _Row(label: l.settingsFaq, onTap: () => _open(AppInfo.faqUrl)),
                      _Row(label: l.settingsRate, onTap: () => _open(storeUrl)),
                      _Row(
                        label: l.settingsShareApp,
                        onTap: () => getIt<ShareService>().shareText('${AppInfo.name} — $storeUrl', subject: AppInfo.name),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.x1),
                Center(
                  child: Text(
                    l.settingsVersion(s.version),
                    style: context.text.bodySmall?.copyWith(color: c.muted),
                  ),
                ),
                const SizedBox(height: Space.x1),
                Center(
                  child: Text(
                    AppInfo.publisher,
                    style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w700, letterSpacing: 3),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(title, padding: const EdgeInsets.only(left: Space.x1, bottom: Space.x2)),
            child,
          ],
        ),
      );
}

/// Rounded card of rows separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.rows});
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: Radii.lgR, border: Border.all(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) Divider(color: c.border, height: 1),
            r,
          ],
        ],
      ),
    );
  }
}

/// Label on the left; value, then a chevron when tappable.
class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.onTap, this.trailing});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.x4, right: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: context.text.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (value != null && value!.isNotEmpty)
                Text(value!, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: c.muted)),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 6),
                AppIcon(AppIcons.chevronRight, size: 16, color: c.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
