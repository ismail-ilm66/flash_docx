import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Viewer banner (feature 3): "Looks like an electricity bill · Rename to
/// '…' · Bills", Apply / ✕. Nothing changes until the user taps Apply.
class SuggestionBanner extends StatelessWidget {
  const SuggestionBanner({required this.suggestion, required this.onApply, required this.onDismiss, super.key});

  final NameSuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Material(
      color: c.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x1, Space.x2),
        child: Row(
          children: [
            AppIcon(AppIcons.bolt, size: 18, color: c.accentText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FitText(
                    l.smartLooksLike(suggestion.kind),
                    textAlign: TextAlign.start,
                    style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 1),
                  FitText(
                    l.smartRenameTo(suggestion.title, folderLabel(context, suggestion.folder)),
                    textAlign: TextAlign.start,
                    style: context.text.bodySmall?.copyWith(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.x2),
            PrimaryButton(label: l.smartApply, onPressed: onApply, expand: false, dense: true, height: 36),
            IconButton(
              tooltip: l.smartDismiss,
              onPressed: onDismiss,
              icon: AppIcon(AppIcons.close, size: 18, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
