import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/date_format.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/page_thumb.dart';
import 'package:flutter/material.dart';

/// Home / search row: thumb, title, meta, activity line, ⋮.
class DocumentTile extends StatelessWidget {
  const DocumentTile({
    required this.document,
    required this.onTap,
    super.key,
    this.onMore,
  });

  final ScanDocument document;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final d = document;
    final cover = d.cover;
    final act = d.lastActivity;
    final activityLine = act == null
        ? DateFmt.relative(d.updatedAt)
        : '${activityLabel(context, act.type)} · ${DateFmt.relative(act.at)}';

    final isCard = d.mode == ScanMode.idCard || d.mode == ScanMode.passport;
    final meta = isCard
        ? '${modeLabel(context, d.mode)} · ${l.pagesCount(d.pages.length)}'
        : l.pagesCount(d.pages.length);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 64,
              decoration: BoxDecoration(color: c.surface2, borderRadius: Radii.smR),
              alignment: Alignment.center,
              child: SizedBox(
                width: isCard ? 42 : 36,
                height: isCard ? 27 : 48,
                child: PageImage(
                  path: cover?.thumbPath ?? cover?.processedPath ?? cover?.originalPath,
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
                    style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(meta, style: context.text.bodySmall?.copyWith(color: c.muted)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      AppIcon(AppIcons.clock, size: 13, color: c.accentText),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          activityLine,
                          style: context.text.bodySmall?.copyWith(color: c.accentText, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onMore != null)
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

String modeLabel(BuildContext context, ScanMode m) {
  final l = context.l10n;
  return switch (m) {
    ScanMode.single => l.modeSingle,
    ScanMode.batch => l.modeBatch,
    ScanMode.idCard => l.modeIdCard,
    ScanMode.passport => l.modePassport,
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
  };
}

String filterLabel(BuildContext context, FilterType f) {
  final l = context.l10n;
  return switch (f) {
    FilterType.original => l.filterOriginal,
    FilterType.auto => l.filterAuto,
    FilterType.colorBoost => l.filterColorBoost,
    FilterType.grayscale => l.filterGrayscale,
    FilterType.bwPrint => l.filterBwPrint,
  };
}
