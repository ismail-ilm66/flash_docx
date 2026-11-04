import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum PageSource { camera, photos, files }

/// Asks where new pages come from (Camera / Photos / Files).
Future<PageSource?> pickPageSource(BuildContext context, {bool camera = true}) {
  final l = context.l10n;
  return AppBottomSheet.show<PageSource>(
    context,
    builder: (ctx) => AppBottomSheet(
      title: l.viewerAddPages,
      padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x4),
      child: Column(
        children: [
          if (camera)
            SheetAction(
              label: l.addFromCamera,
              leading: const AppIcon(AppIcons.camera),
              onTap: () => Navigator.of(ctx).pop(PageSource.camera),
            ),
          SheetAction(
            label: l.homeImportGallery,
            leading: const AppIcon(AppIcons.gallery),
            onTap: () => Navigator.of(ctx).pop(PageSource.photos),
          ),
          SheetAction(
            label: l.homeImportFiles,
            leading: const AppIcon(AppIcons.files),
            onTap: () => Navigator.of(ctx).pop(PageSource.files),
          ),
        ],
      ),
    ),
  );
}

/// Source sheet → capture or import → the same prepare pipeline as every
/// other entry point. Resolves the new draft pages, or null if cancelled.
Future<List<ScanPage>?> collectNewPages(BuildContext context, {required ScanMode mode}) async {
  final source = await pickPageSource(context);
  if (source == null || !context.mounted) return null;
  final captureMode = mode == ScanMode.single ? ScanMode.batch : mode;
  if (source == PageSource.camera) {
    return context.push<List<ScanPage>>(
      Routes.camera,
      extra: CameraArgs(mode: captureMode, returnPages: true),
    );
  }
  final svc = getIt<ImportService>();
  final picked = source == PageSource.photos ? await svc.fromGallery() : await svc.fromFiles();
  if (!context.mounted) return null;
  final paths = picked.fold<List<String>?>(
    (f) {
      if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      return null;
    },
    (p) => p,
  );
  if (paths == null || paths.isEmpty) return null;
  final prepared = await getIt<PreparePages>()(paths, mode: captureMode);
  if (!context.mounted) return null;
  return prepared.fold(
    (f) {
      context.showSnack(failureMessage(context, f), error: true);
      return null;
    },
    (pages) => pages,
  );
}
