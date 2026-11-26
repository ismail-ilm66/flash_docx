import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

/// Round 11b, I3: before a "Save to phone" on Android 9 and below, a
/// one-line reason for the storage permission. True to go ahead.
Future<bool> readyToSave(BuildContext context) async {
  if (!await getIt<SaveService>().needsPermission()) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  return AppDialog.confirm(
    context,
    title: l.saveNeedsStorageTitle,
    body: l.saveNeedsStorageBody,
    confirmLabel: l.reduceContinue,
    cancelLabel: l.commonCancel,
  );
}

/// "Saved to Pictures/Flash Dox" with Open (round 11b, I3).
void showSaved(BuildContext context) {
  final l = context.l10n;
  final svc = getIt<SaveService>();
  final s = svc.lastSaved;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(s == null || s.folder.isEmpty ? l.shareSaved : l.savedTo(s.folder)),
        persist: false,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: s == null || s.uri.isEmpty
            ? null
            : SnackBarAction(label: l.saveOpen, textColor: context.colors.accent, onPressed: svc.openLast),
      ),
    );
}
