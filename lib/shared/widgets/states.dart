import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/buttons.dart';
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    super.key,
    this.body,
    this.icon = AppIcons.document,
    this.action,
  });

  final String title;
  final String? body;
  final AppIcons icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: Radii.xlR,
              ),
              child: AppIcon(icon, size: 32, color: c.accentText),
            ),
            const SizedBox(height: Space.x5),
            Text(
              title,
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: Space.x2),
              Text(
                body!,
                style: context.text.bodyMedium?.copyWith(color: c.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.x6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.failure, this.message, this.onRetry});

  final Failure? failure;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return EmptyState(
      icon: AppIcons.warning,
      title: message ?? failureMessage(context, failure),
      action: onRetry == null
          ? null
          : SecondaryButton(
              label: l.commonRetry,
              onPressed: onRetry,
              expand: false,
              icon: AppIcons.retake,
            ),
    );
  }
}

String failureMessage(BuildContext context, Failure? f) {
  final l = context.l10n;
  return switch (f) {
    StorageFailure() => l.errorStorage,
    ImageProcessingFailure() => l.errorImage,
    OcrFailure() => l.errorOcr,
    PdfFailure() => l.errorPdf,
    PermissionFailure() => l.errorPermission,
    OfflineFailure() => l.errorOffline,
    _ => l.errorGeneric,
  };
}

/// Full-screen scrim with a spinner and optional label / progress.
class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({super.key, this.label, this.progress});

  final String? label;

  /// 0..1 or null for indeterminate.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AbsorbPointer(
      child: ColoredBox(
        color: c.bg.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(Space.x6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: Radii.xlR,
              border: Border.all(color: c.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(height: Space.x4),
                  Text(label!, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
