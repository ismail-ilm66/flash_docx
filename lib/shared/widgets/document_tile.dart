import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/bytes.dart';
import 'package:flash_dox/core/utils/date_format.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/page_thumb.dart';
import 'package:flutter/material.dart';

/// Home / search row: thumb, title, one meta line ("Other · 4 pages ·
/// 1.6 MB · Today", round 11), ⋮. [compact] (the "Pick a document" sheet)
/// is the same row without ⋮ or selection.
class DocumentTile extends StatelessWidget {
  const DocumentTile({
    required this.document,
    required this.onTap,
    super.key,
    this.onMore,
    this.compact = false,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final ScanDocument document;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool compact;

  /// Round 10, P1-5: long-press starts selecting; while [selecting], a
  /// checkbox replaces ⋮.
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final d = document;
    final cover = d.cover;
    final isCard = d.mode == ScanMode.idCard || d.mode == ScanMode.passport;
    // Round 11: the date joins the meta line.
    final meta = '${documentMeta(context, d)} · ${_when(context, d.updatedAt)}';
    final ticked = selecting && selected;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          // Round 11, P0-2: selected rows get an amber tint.
          color: ticked ? c.accentSoft : null,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 64,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: Radii.smR,
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: isCard ? 42 : 36,
                height: isCard ? 27 : 48,
                child: PageImage(
                  path: cover?.listImagePath,
                  cacheKey: cover?.thumbPath ?? cover?.processedPath,
                  cacheWidth: 120,
                  radius: isCard ? 4 : 3,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    style: context.text.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: context.text.bodySmall?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            if (selecting)
              // Filled amber when ticked, an empty grey box when not.
              Semantics(
                checked: selected,
                child: SizedBox(
                  width: Sizes.tap,
                  height: Sizes.tap,
                  child: Center(
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: selected ? c.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: selected ? c.accent : c.muted, width: 1.6),
                      ),
                      child: selected ? Icon(Icons.check_rounded, size: 16, color: c.onAccent) : null,
                    ),
                  ),
                ),
              )
            else if (onMore != null)
              IconButton(
                onPressed: onMore,
                icon: AppIcon(AppIcons.more, size: 20, color: c.muted),
                tooltip: l.commonMore,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", "Nov 23" (round 11 meta line).
String _when(BuildContext context, DateTime d) {
  final l = context.l10n;
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return l.dateToday;
  if (day == today.subtract(const Duration(days: 1))) return l.dateYesterday;
  return DateFmt.day(d);
}

String folderLabel(BuildContext context, DocFolder f) {
  final l = context.l10n;
  return switch (f) {
    DocFolder.bills => l.folderBills,
    DocFolder.ids => l.folderIds,
    DocFolder.education => l.folderEducation,
    DocFolder.receipts => l.folderReceipts,
    DocFolder.office => l.folderOffice,
    DocFolder.photos => l.folderPhotos,
    DocFolder.other => l.folderOther,
  };
}

/// "Bills · 2 pages · 840 KB", "IDs · ID card · 2 sides" (feature 3).
String documentMeta(BuildContext context, ScanDocument d) {
  final l = context.l10n;
  final folder = folderLabel(context, d.folder);
  if (d.mode != ScanMode.document) {
    final n = d.pages.length;
    // Round 10, P1-8: passport photos are kept as a "Photo sheet".
    if (d.mode == ScanMode.photo) return '$folder · ${l.photoSheetType}';
    return '$folder · ${modeLabel(context, d.mode)} · ${d.mode == ScanMode.idCard ? l.sidesCount(n) : l.pagesCount(n)}';
  }
  return [folder, l.pagesCount(d.pages.length), if (d.sizeBytes > 0) formatBytes(d.sizeBytes)].join(' · ');
}

String modeLabel(BuildContext context, ScanMode m) {
  final l = context.l10n;
  return switch (m) {
    ScanMode.document => l.modeDocument,
    ScanMode.idCard => l.modeIdCard,
    ScanMode.passport => l.modePassport,
    ScanMode.photo => l.modePhoto,
  };
}

String activityLabel(BuildContext context, ActivityType t) {
  final l = context.l10n;
  return switch (t) {
    ActivityType.created => l.activityCreated,
    ActivityType.edited => l.activityEdited,
    ActivityType.sharedPdf => l.activitySharedPdf,
    ActivityType.sharedImages => l.activitySharedImages,
    ActivityType.savedToPhone => l.activitySavedToPhone,
    ActivityType.textCopied => l.activityTextCopied,
    ActivityType.printLayout => l.activityPrintLayout,
    ActivityType.signed => l.activitySigned,
    ActivityType.photoSheet => l.activityPhotoSheet,
  };
}

String filterLabel(BuildContext context, FilterType f) {
  final l = context.l10n;
  return switch (f) {
    FilterType.original => l.filterOriginal,
    FilterType.auto => l.filterAuto,
    FilterType.colorBoost => l.filterColorBoost,
    FilterType.grayscale => l.filterGrayscale,
    FilterType.idColor => l.filterIdColor,
    FilterType.bwPrint => l.filterBwPrint,
  };
}
