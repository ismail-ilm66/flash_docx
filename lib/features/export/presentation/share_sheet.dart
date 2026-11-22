import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/bytes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
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
      child: const SharePanel(),
    ),
  );
}

/// The share options. In the sheet by default; [inline] lays them out on a
/// page instead (passport photo, single photo) and stays put when done.
/// Needs an [ExportBloc] above it.
class SharePanel extends StatefulWidget {
  const SharePanel({super.key, this.inline = false});

  final bool inline;

  @override
  State<SharePanel> createState() => _SharePanelState();
}

class _SharePanelState extends State<SharePanel> {
  late final TextEditingController _name;

  /// More options, open as the user last left it (round 10, P1-1).
  bool _moreOpen = getIt<PrefsService>().shareMoreOpen;

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
          if (!widget.inline) Navigator.of(context).pop();
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
        final isIdCard = s.document.mode == ScanMode.idCard;
        // Round 10, P1-2: ID cards are shared as images first.
        final formats = s.document.mode == ScanMode.photo
            ? const [ExportFormat.jpg, ExportFormat.png]
            : isIdCard
            ? const [ExportFormat.jpg, ExportFormat.pdf, ExportFormat.png]
            : ExportFormat.values;
        String formatLabel(ExportFormat f) => isIdCard && f == ExportFormat.jpg ? l.shareImages : formatName(f);
        String perPage(ExportQuality q) =>
            l.shareQualityPerPage(formatBytes(ExportDocument.estimatePageBytes(o.copyWith(quality: q))));
        final layoutShown = s.document.mode.supportsPrintLayout && s.document.pages.length >= 2;
        final more = <Widget>[
          if (!o.isImage) ...[
            SectionLabel(l.sharePageSize, padding: const EdgeInsets.only(bottom: Space.x2)),
            for (final p in PdfPageSize.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x2),
                child: _PageSizeOption(
                  size: p,
                  label: switch (p) {
                    PdfPageSize.auto => l.sharePageAutoRecommended,
                    PdfPageSize.a4 => l.sharePageA4,
                    PdfPageSize.letter => l.sharePageLetter,
                    PdfPageSize.fit => l.sharePageFit,
                  },
                  hint: p == PdfPageSize.fit ? l.sharePageFitHint : null,
                  selected: o.pageSize == p,
                  onTap: () => _update(o.copyWith(pageSize: p)),
                ),
              ),
            const SizedBox(height: Space.x2),
          ],
          if (layoutShown) ...[
            SectionLabel(l.shareLayout, padding: const EdgeInsets.only(bottom: Space.x2)),
            SegmentedPills<ExportLayout>(
              values: ExportLayout.values,
              selected: o.layout,
              labelOf: (v) => v == ExportLayout.oneImage ? l.shareLayoutOneImage : l.shareLayoutSeparate,
              onChanged: (v) => _update(o.copyWith(layout: v)),
            ),
            gap,
          ],
          // Passport photo: the exact pixels an online form asks for.
          if (s.document.mode == ScanMode.photo) ...[
            _SettingRow(
              title: l.shareImageSize,
              hint: l.shareImageSizeHint,
              value: imageSizeLabel(context, o.hasPixelSize ? (width: o.pixelWidth!, height: o.pixelHeight!) : null),
              onTap: () async {
                final e = s.document.cover?.edits;
                final picked = await showImageSizeSheet(
                  context,
                  current: o.hasPixelSize ? (width: o.pixelWidth!, height: o.pixelHeight!) : null,
                  widthMm: e?.photoWidthMm ?? 35,
                  heightMm: e?.photoHeightMm ?? 45,
                );
                if (picked == null || !context.mounted) return;
                final cur = context.read<ExportBloc>().state.options;
                _update(cur.copyWith(pixelWidth: picked.size?.width, pixelHeight: picked.size?.height));
              },
            ),
            const SizedBox(height: Space.x3),
          ],
          // Round 10, P1-6: the same switch as in Settings.
          if (PageFooter.appliesTo(s.document))
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l.shareFooter, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
              value: o.footer,
              onChanged: (v) {
                _update(o.copyWith(footer: v));
                unawaited(getIt<PrefsService>().setExportFooter(v));
              },
            ),
          if (ExportDocument.canShrink(s.document, o)) ...[
            _SettingRow(
              title: l.shareMaxSize,
              hint: l.shareMaxSizeHint,
              value: maxSizeLabel(context, o.maxBytes),
              onTap: () async {
                final picked = await showMaxSizeSheet(context, o.maxBytes, photo: s.document.mode == ScanMode.photo);
                if (picked == null || !context.mounted) return;
                final cur = context.read<ExportBloc>().state.options;
                _update(cur.copyWith(maxBytes: picked.bytes, grayscaleToFit: false));
              },
            ),
            const SizedBox(height: Space.x3),
          ],
        ];
        final top = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Round 10, P1-1: file name · format · quality, the rest under
            // More options.
            SectionLabel(l.shareFileName, padding: const EdgeInsets.only(bottom: 6)),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                suffixText: '.${o.extension}',
                suffixStyle: context.text.bodyMedium?.copyWith(color: c.muted, fontWeight: FontWeight.w600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.borderStrong)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.borderStrong)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent, width: 1.5)),
              ),
            ),
            gap,
            SectionLabel(l.shareFormat, padding: const EdgeInsets.only(bottom: Space.x2)),
            Row(
              children: [
                for (final (i, f) in formats.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.x2),
                  Expanded(
                    child: OptionCard(
                      centered: true,
                      height: 64,
                      titleSize: 15,
                      title: formatLabel(f),
                      subtitle: f == ExportFormat.pdf ? l.shareOneFile : l.shareImagesCount(pageCount),
                      selected: o.format == f,
                      gated: f == ExportFormat.png && !s.unlocked.contains(PremiumFeature.pngExport),
                      onTap: () => _update(o.copyWith(format: f)),
                    ),
                  ),
                ],
              ],
            ),
            gap,
            SectionLabel(l.shareQuality, padding: const EdgeInsets.only(bottom: Space.x2)),
            Row(
              children: [
                Expanded(
                  child: OptionCard(
                    height: 56,
                    title: l.shareQualityStandard,
                    subtitle: perPage(ExportQuality.standard),
                    selected: o.quality == ExportQuality.standard,
                    onTap: () => _update(o.copyWith(quality: ExportQuality.standard)),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: OptionCard(
                    height: 56,
                    title: l.shareQualityHigh,
                    subtitle: perPage(ExportQuality.high),
                    selected: o.quality == ExportQuality.high,
                    gated: !s.unlocked.contains(PremiumFeature.highQualityExport),
                    onTap: () => _update(o.copyWith(quality: ExportQuality.high)),
                  ),
                ),
              ],
            ),
            if (more.isNotEmpty) ...[
              const SizedBox(height: Space.x3),
              _MoreOptions(
                label: l.shareMoreOptions,
                open: _moreOpen,
                onToggle: () {
                  setState(() => _moreOpen = !_moreOpen);
                  unawaited(getIt<PrefsService>().setShareMoreOpen(_moreOpen));
                },
                children: more,
              ),
            ],
          ],
        );
        final bottom = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (preparing || working) ...[
              LinearProgressIndicator(
                value: prep == null || prep.done == 0 || prep.ready ? null : prep.done / prep.total,
                borderRadius: Radii.pillR,
              ),
              const SizedBox(height: Space.x2),
              Text(
                !preparing
                    ? l.sharePreparing
                    : ExportDocument.shrinks(s.document, o) && prep.done >= pageCount
                    ? l.shareShrinking
                    : l.sharePreparingPages(prep.done.clamp(0, pageCount), pageCount),
                style: context.text.bodySmall?.copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.x3),
            ],
            if (!preparing && !working && prep != null) ..._result(context, prep, o),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: l.shareSaveToPhone,
                    icon: AppIcons.save,
                    dense: true,
                    onPressed: working ? null : () => _go(ExportTarget.saveToPhone),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: l.shareButtonFormat(formatLabel(o.format)),
                    icon: AppIcons.share,
                    loading: working,
                    onPressed: working ? null : () => _go(ExportTarget.share),
                  ),
                ),
              ],
            ),
          ],
        );
        if (widget.inline) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [top, const SizedBox(height: 22), bottom],
          );
        }
        return AppBottomSheet(
          title: l.shareTitle,
          subtitle: '${s.document.title} · ${l.pagesCount(pageCount)}',
          footer: bottom,
          child: top,
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

/// "More options ›": one row, closed by default; the options under it when
/// open (round 10, P1-1).
class _MoreOptions extends StatelessWidget {
  const _MoreOptions({required this.label, required this.open, required this.onToggle, required this.children});
  final String label;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.tap),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: Motion.fast,
                  child: AppIcon(AppIcons.chevronRight, size: 18, color: c.muted),
                ),
              ],
            ),
          ),
        ),
        if (open) ...[const SizedBox(height: Space.x2), ...children],
      ],
    );
  }
}

/// A page size with a small icon of its shape (round 10, P1-1).
class _PageSizeOption extends StatelessWidget {
  const _PageSizeOption({required this.size, required this.label, required this.selected, required this.onTap, this.hint});
  final PdfPageSize size;
  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.accentText : c.text;
    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? c.accent : c.borderStrong, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(width: 22, height: 26, child: CustomPaint(painter: _PageShapePainter(size, fg))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: fg)),
                    if (hint != null)
                      Text(hint!, style: context.text.labelSmall?.copyWith(fontSize: 11, color: c.muted)),
                  ],
                ),
              ),
              if (selected) AppIcon(AppIcons.check, size: 18, color: c.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageShapePainter extends CustomPainter {
  const _PageShapePainter(this.size, this.color);
  final PdfPageSize size;
  final Color color;

  @override
  void paint(Canvas canvas, Size box) {
    // A4 1 : 1.414, Letter 1 : 1.294; Auto is A4 that fills, Same as scan a
    // freer shape (a receipt).
    final aspect = switch (size) {
      PdfPageSize.letter => 1 / 1.294,
      PdfPageSize.fit => 1 / 1.9,
      _ => 1 / 1.414,
    };
    final h = box.height;
    final w = h * aspect;
    final r = Rect.fromLTWH((box.width - w) / 2, 0, w, h);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), stroke);
    if (size == PdfPageSize.auto) {
      // The image filling the page.
      canvas.drawRect(r.deflate(3), Paint()..color = color.withValues(alpha: 0.35));
    }
  }

  @override
  bool shouldRepaint(covariant _PageShapePainter old) => old.size != size || old.color != color;
}
