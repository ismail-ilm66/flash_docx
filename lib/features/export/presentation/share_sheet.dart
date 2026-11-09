import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/bytes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart';
import 'package:flash_dox/features/export/presentation/image_size_sheet.dart';
import 'package:flash_dox/features/export/presentation/max_size_sheet.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/rewards/presentation/unlock_dialog.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Share / save bottom sheet (§11). Starts building the default export as
/// soon as it opens (P0-4).
Future<void> showShareSheet(
  BuildContext context,
  ScanDocument doc, {
  ExportOptions Function(ExportOptions defaults)? options,
}) {
  getIt<RewardGate>().preload();
  return AppBottomSheet.show<void>(
    context,
    builder: (_) => BlocProvider(
      create: (_) {
        final bloc = getIt<ExportBloc>(param1: doc);
        if (options != null) {
          bloc.add(ExportOptionsChanged(options(bloc.state.options)));
        }
        return bloc..add(const ExportSheetOpened());
      },
      child: const _ShareSheet(),
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet();

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: context.read<ExportBloc>().state.options.fileName,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _update(ExportOptions o) =>
      context.read<ExportBloc>().add(ExportOptionsChanged(o));

  Future<void> _go(ExportTarget target) async {
    final bloc = context.read<ExportBloc>();
    _update(bloc.state.options.copyWith(fileName: _name.text));
    final needed = bloc.state.requiredUnlock;
    if (needed != null) {
      final ok = await showUnlockDialog(context, needed);
      if (!ok || !mounted) return;
      bloc.add(ExportFeatureUnlocked(needed));
    }
    bloc.add(ExportRequested(target));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<ExportBloc, ExportState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        final st = s.status;
        if (st is ExportDone) {
          if (st.target == ExportTarget.saveToPhone) {
            context.showSnack(l.shareSaved);
          }
          Navigator.of(context).pop();
        } else if (st is ExportFailed) {
          final f = st.failure;
          context.showSnack(
            f is PermissionFailure
                ? l.errorPermission
                : failureMessage(context, f),
            error: true,
          );
        }
      },
      builder: (context, s) {
        final o = s.options;
        final working = s.status is ExportWorking;
        final prep = s.prep;
        // "Preparing… 2/3 pages" while the file builds in the background;
        // Share stays tappable and waits for it.
        final preparing = prep != null && !prep.ready && prep.done < prep.total;
        final pageCount = s.document.pages.length;
        String formatName(ExportFormat f) => switch (f) {
          ExportFormat.pdf => l.sharePdf,
          ExportFormat.jpg => l.shareJpg,
          ExportFormat.png => l.sharePng,
        };
        const gap = SizedBox(height: 18);
        return AppBottomSheet(
          title: l.shareTitle,
          subtitle: '${s.document.title} · ${l.pagesCount(pageCount)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                l.shareFormat,
                padding: const EdgeInsets.only(bottom: Space.x2),
              ),
              Row(
                children: [
                  // A passport photo is a picture: JPG or PNG, no PDF.
                  for (final (i, f)
                      in (s.document.mode == ScanMode.photo
                              ? const [ExportFormat.jpg, ExportFormat.png]
                              : ExportFormat.values)
                          .indexed) ...[
                    if (i > 0) const SizedBox(width: Space.x2),
                    Expanded(
                      child: OptionCard(
                        centered: true,
                        height: 64,
                        titleSize: 15,
                        title: formatName(f),
                        subtitle: f == ExportFormat.pdf
                            ? l.shareOneFile
                            : l.shareImagesCount(pageCount),
                        selected: o.format == f,
                        gated:
                            f == ExportFormat.png &&
                            !s.unlocked.contains(PremiumFeature.pngExport),
                        onTap: () => _update(o.copyWith(format: f)),
                      ),
                    ),
                  ],
                ],
              ),
              if (s.document.mode.supportsPrintLayout &&
                  s.document.pages.length >= 2) ...[
                const SizedBox(height: Space.x4),
                SectionLabel(
                  l.shareLayout,
                  padding: const EdgeInsets.only(bottom: Space.x2),
                ),
                SegmentedPills<ExportLayout>(
                  values: ExportLayout.values,
                  selected: o.layout,
                  labelOf: (v) => v == ExportLayout.oneImage
                      ? l.shareLayoutOneImage
                      : l.shareLayoutSeparate,
                  onChanged: (v) => _update(o.copyWith(layout: v)),
                ),
              ],
              if (!o.isImage) ...[
                gap,
                SectionLabel(
                  l.sharePageSize,
                  padding: const EdgeInsets.only(bottom: Space.x2),
                ),
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    for (final p in PdfPageSize.values)
                      OptionChip(
                        label: switch (p) {
                          PdfPageSize.a4 => l.sharePageA4,
                          PdfPageSize.letter => l.sharePageLetter,
                          PdfPageSize.fit => l.sharePageFit,
                        },
                        selected: o.pageSize == p,
                        onTap: () => _update(o.copyWith(pageSize: p)),
                      ),
                  ],
                ),
              ],
              gap,
              SectionLabel(
                l.shareQuality,
                padding: const EdgeInsets.only(bottom: Space.x2),
              ),
              Row(
                children: [
                  Expanded(
                    child: OptionCard(
                      height: 56,
                      title: l.shareQualityStandard,
                      subtitle: l.shareQualityStandardHint,
                      selected: o.quality == ExportQuality.standard,
                      onTap: () =>
                          _update(o.copyWith(quality: ExportQuality.standard)),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: OptionCard(
                      height: 56,
                      title: l.shareQualityHigh,
                      subtitle: l.shareQualityHighHint,
                      selected: o.quality == ExportQuality.high,
                      gated: !s.unlocked.contains(
                        PremiumFeature.highQualityExport,
                      ),
                      onTap: () =>
                          _update(o.copyWith(quality: ExportQuality.high)),
                    ),
                  ),
                ],
              ),
              // Passport photo: the exact pixels an online form asks for.
              if (s.document.mode == ScanMode.photo) ...[
                const SizedBox(height: Space.x3),
                _SettingRow(
                  title: l.shareImageSize,
                  hint: l.shareImageSizeHint,
                  value: imageSizeLabel(
                    context,
                    o.hasPixelSize
                        ? (width: o.pixelWidth!, height: o.pixelHeight!)
                        : null,
                  ),
                  onTap: () async {
                    final e = s.document.cover?.edits;
                    final picked = await showImageSizeSheet(
                      context,
                      current: o.hasPixelSize
                          ? (width: o.pixelWidth!, height: o.pixelHeight!)
                          : null,
                      widthMm: e?.photoWidthMm ?? 35,
                      heightMm: e?.photoHeightMm ?? 45,
                    );
                    if (picked == null || !context.mounted) return;
                    final cur = context.read<ExportBloc>().state.options;
                    _update(
                      cur.copyWith(
                        pixelWidth: picked.size?.width,
                        pixelHeight: picked.size?.height,
                      ),
                    );
                  },
                ),
              ],
              if (ExportDocument.canShrink(s.document, o)) ...[
                const SizedBox(height: Space.x3),
                _SettingRow(
                  title: l.shareMaxSize,
                  hint: l.shareMaxSizeHint,
                  value: maxSizeLabel(context, o.maxBytes),
                  onTap: () async {
                    final picked = await showMaxSizeSheet(
                      context,
                      o.maxBytes,
                      photo: s.document.mode == ScanMode.photo,
                    );
                    if (picked == null || !context.mounted) return;
                    final cur = context.read<ExportBloc>().state.options;
                    _update(
                      cur.copyWith(
                        maxBytes: picked.bytes,
                        grayscaleToFit: false,
                      ),
                    );
                  },
                ),
              ],
              gap,
              SectionLabel(
                l.shareFileName,
                padding: const EdgeInsets.only(bottom: 6),
              ),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  suffixText: '.${o.extension}',
                  suffixStyle: context.text.bodyMedium?.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderStrong),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (preparing || working) ...[
                LinearProgressIndicator(
                  value: prep == null || prep.done == 0 || prep.ready
                      ? null
                      : prep.done / prep.total,
                  borderRadius: Radii.pillR,
                ),
                const SizedBox(height: Space.x2),
                Text(
                  !preparing
                      ? l.sharePreparing
                      : ExportDocument.shrinks(s.document, o) &&
                            prep.done >= pageCount
                      ? l.shareShrinking
                      : l.sharePreparingPages(
                          prep.done.clamp(0, pageCount),
                          pageCount,
                        ),
                  style: context.text.bodySmall?.copyWith(color: c.muted),
                ),
                const SizedBox(height: Space.x3),
              ],
              if (!preparing && !working && prep != null)
                ..._result(context, prep, o),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l.shareSaveToPhone,
                      icon: AppIcons.save,
                      dense: true,
                      onPressed: working
                          ? null
                          : () => _go(ExportTarget.saveToPhone),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: l.shareButtonFormat(formatName(o.format)),
                      icon: AppIcons.share,
                      loading: working,
                      onPressed: working ? null : () => _go(ExportTarget.share),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Max file size outcome above the buttons: the final size, a readability
/// warning, or why it couldn't fit (with the black and white offer).
List<Widget> _result(BuildContext context, ExportPrep prep, ExportOptions o) {
  final l = context.l10n;
  final c = context.colors;
  final f = prep.failure;
  Widget line(String text, {Color? color, FontWeight? weight}) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: Text(
      text,
      style: context.text.bodySmall?.copyWith(
        color: color ?? c.muted,
        fontWeight: weight,
      ),
    ),
  );
  if (f is ShrinkFailure) {
    return [
      line(
        o.format == ExportFormat.pdf
            ? failureMessage(context, f)
            : l.sharePhotoCantFit(formatBytes(f.targetBytes)),
        color: c.danger,
        weight: FontWeight.w600,
      ),
      if (f.canTryGrayscale)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.x3),
          child: SecondaryButton(
            label: l.shareMakeGrayscale,
            dense: true,
            onPressed: () => context.read<ExportBloc>().add(
              ExportOptionsChanged(o.copyWith(grayscaleToFit: true)),
            ),
          ),
        ),
    ];
  }
  if (prep.bytes == null) return const [];
  return [
    line(
      l.shareReadySize(formatBytes(prep.bytes!)),
      color: c.text,
      weight: FontWeight.w700,
    ),
    if (prep.hardToRead) line(l.shareHardToRead),
  ];
}

/// "Max file size · Under 500 KB ›" (artboard *Export*).
/// A setting that opens its own sheet: title, hint, current value ›
/// (artboard *Export*: Max file size; also Image size for photos).
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String hint;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(14, Space.x2, 12, Space.x2),
        decoration: BoxDecoration(
          border: Border.all(color: c.borderStrong),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FitText(
                    title,
                    textAlign: TextAlign.start,
                    style: context.text.titleSmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: context.text.labelSmall?.copyWith(
                      fontSize: 11,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FitText(
                value,
                textAlign: TextAlign.end,
                style: context.text.labelLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.accentText,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(AppIcons.chevronRight, size: 16, color: c.accentText),
          ],
        ),
      ),
    );
  }
}
