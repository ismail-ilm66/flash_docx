import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

enum DocumentMenuAction { rename, share, delete }

/// ⋮ menu for a document row. Returns the chosen action.
Future<DocumentMenuAction?> showDocumentMenu(
  BuildContext context,
  ScanDocument doc,
) {
  final l = context.l10n;
  return AppBottomSheet.show<DocumentMenuAction>(
    context,
    builder: (ctx) => AppBottomSheet(
      title: doc.title,
      child: Column(
        children: [
          SheetAction(
            label: l.viewerRename,
            leading: const AppIcon(AppIcons.rename),
            onTap: () => Navigator.of(ctx).pop(DocumentMenuAction.rename),
          ),
          SheetAction(
            label: l.viewerShare,
            leading: const AppIcon(AppIcons.share),
            onTap: () => Navigator.of(ctx).pop(DocumentMenuAction.share),
          ),
          SheetAction(
            label: l.viewerDelete,
            leading: const AppIcon(AppIcons.delete),
            destructive: true,
            onTap: () => Navigator.of(ctx).pop(DocumentMenuAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// Rename + delete flows shared by Home and Viewer.
Future<bool> renameDocumentFlow(
  BuildContext context,
  ScanDocument doc,
  Future<Object?> Function(String title) rename,
) async {
  final l = context.l10n;
  final title = await AppDialog.prompt(
    context,
    title: l.renameTitle,
    hint: l.renameHint,
    initial: doc.title,
    confirmLabel: l.commonSave,
  );
  if (title == null || title == doc.title) return false;
  final err = await rename(title);
  if (err != null && context.mounted) {
    context.showSnack(l.errorGeneric, error: true);
    return false;
  }
  return true;
}

Future<bool> deleteDocumentFlow(
  BuildContext context,
  ScanDocument doc,
  Future<Object?> Function() delete,
) async {
  final l = context.l10n;
  final ok = await AppDialog.confirm(
    context,
    title: l.deleteDocTitle,
    body: l.deleteDocBody,
    confirmLabel: l.commonDelete,
    destructive: true,
  );
  if (!ok) return false;
  final err = await delete();
  if (err != null && context.mounted) {
    context.showSnack(l.errorGeneric, error: true);
    return false;
  }
  return true;
}
