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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final storeUrl = Platform.isIOS ? AppInfo.appStoreUrl : AppInfo.playStoreUrl;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, s) {
        final cubit = context.read<SettingsCubit>();
        return AppScaffold(
          topBar: AppTopBar(title: l.settingsTitle, leading: TopBarLeading.none),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Sizes.navBar + Space.x8),
            children: [
              _Section(l.settingsAppearance),
              _Card(
                children: [
                  _RowLabel(l.settingsTheme),
                  BlocBuilder<ThemeCubit, ThemeMode>(
                    builder: (context, mode) => SegmentedPills<ThemeMode>(
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
                ],
              ),
              _Section(l.settingsScan),
              _Card(
                children: [
                  _RowLabel(l.settingsDefaultMode),
                  SegmentedPills<ScanMode>(
                    values: ScanMode.values,
                    selected: s.defaultMode,
                    labelOf: (m) => modeLabel(context, m),
                    onChanged: cubit.setDefaultMode,
                  ),
                  const SizedBox(height: Space.x4),
                  _RowLabel(l.settingsDefaultFilter),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x2,
                    children: [
                      for (final f in FilterType.values)
                        OptionChip(
                          label: filterLabel(context, f),
                          selected: s.defaultFilter == f,
                          onTap: () => cubit.setDefaultFilter(f),
                        ),
                    ],
                  ),
                ],
              ),
              _Section(l.settingsShare),
              _Card(
                children: [
                  _RowLabel(l.settingsDefaultFormat),
                  SegmentedPills<ExportFormat>(
                    values: const [ExportFormat.pdf, ExportFormat.jpg],
                    selected: s.defaultFormat == ExportFormat.png ? ExportFormat.jpg : s.defaultFormat,
                    labelOf: (f) => f == ExportFormat.pdf ? l.sharePdf : l.shareJpg,
                    onChanged: cubit.setDefaultFormat,
                  ),
                  const SizedBox(height: Space.x4),
                  _RowLabel(l.settingsDefaultPageSize),
                  SegmentedPills<PdfPageSize>(
                    values: PdfPageSize.values,
                    selected: s.defaultPageSize,
                    labelOf: (p) => switch (p) {
                      PdfPageSize.a4 => l.sharePageA4,
                      PdfPageSize.letter => l.sharePageLetter,
                      PdfPageSize.fit => l.sharePageFit,
                    },
                    onChanged: cubit.setDefaultPageSize,
                  ),
                ],
              ),
              _Section(l.settingsStorage),
              _Card(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const AppIcon(AppIcons.storage),
                    title: Text(l.settingsStorageUsed),
                    trailing: Text(_bytes(s.storageBytes), style: context.text.labelLarge?.copyWith(color: c.muted)),
                  ),
                  Divider(color: c.border, height: 1),
                  ListTile(
                    leading: const AppIcon(AppIcons.delete),
                    title: Text(l.settingsClearTemp),
                    trailing: s.clearing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : AppIcon(AppIcons.chevronRight, color: c.muted),
                    onTap: s.clearing
                        ? null
                        : () async {
                            await cubit.clearTemp();
                            if (context.mounted) context.showSnack(l.settingsClearedTemp);
                          },
                  ),
                ],
              ),
              _Section(l.settingsAbout),
              _Card(
                padding: EdgeInsets.zero,
                children: [
                  _LinkTile(icon: AppIcons.privacy, label: l.settingsPrivacy, onTap: () => _open(AppInfo.privacyPolicyUrl)),
                  Divider(color: c.border, height: 1),
                  _LinkTile(icon: AppIcons.faq, label: l.settingsFaq, onTap: () => _open(AppInfo.faqUrl)),
                  Divider(color: c.border, height: 1),
                  _LinkTile(icon: AppIcons.star, label: l.settingsRate, onTap: () => _open(storeUrl)),
                  Divider(color: c.border, height: 1),
                  _LinkTile(
                    icon: AppIcons.share,
                    label: l.settingsShareApp,
                    onTap: () => getIt<ShareService>().shareText('${AppInfo.name} — $storeUrl', subject: AppInfo.name),
                  ),
                ],
              ),
              const SizedBox(height: Space.x4),
              Center(
                child: Text(
                  l.settingsVersion(s.version),
                  style: context.text.bodySmall?.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.x1, Space.x5, Space.x1, Space.x2),
        child: Text(text, style: context.text.titleMedium?.copyWith(color: context.colors.muted)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.all(Space.x4)});
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: c.surface, borderRadius: Radii.lgR, border: Border.all(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.x2),
        child: Text(text, style: context.text.labelMedium?.copyWith(color: context.colors.muted)),
      );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.label, required this.onTap});
  final AppIcons icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: AppIcon(icon),
        title: Text(label),
        trailing: AppIcon(AppIcons.chevronRight, color: context.colors.muted),
        onTap: onTap,
      );
}
