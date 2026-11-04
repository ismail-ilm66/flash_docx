import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/buttons.dart';
import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    super.key,
    this.body,
    this.content,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructive = false,
    this.primaryLoading = false,
  });

  final String title;
  final String? body;
  final Widget? content;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool destructive;
  final bool primaryLoading;

  /// Confirm dialog. Resolves true when the primary action is tapped.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        body: body,
        destructive: destructive,
        primaryLabel: confirmLabel,
        onPrimary: () => Navigator.of(ctx).pop(true),
        secondaryLabel: ctx.l10n.commonCancel,
        onSecondary: () => Navigator.of(ctx).pop(false),
      ),
    );
    return r ?? false;
  }

  /// Single-field text prompt. Resolves the trimmed text or null.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    required String hint,
    required String confirmLabel,
    String? initial,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(
        title: title,
        hint: hint,
        initial: initial,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(Space.x6),
      child: Padding(
        padding: const EdgeInsets.all(Space.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.text.titleLarge),
            if (body != null) ...[
              const SizedBox(height: Space.x2),
              Text(body!, style: context.text.bodyMedium?.copyWith(color: c.muted)),
            ],
            if (content != null) ...[
              const SizedBox(height: Space.x4),
              content!,
            ],
            const SizedBox(height: Space.x5),
            if (primaryLabel != null)
              destructive
                  ? SecondaryButton(
                      label: primaryLabel!,
                      onPressed: onPrimary,
                      destructive: true,
                      loading: primaryLoading,
                    )
                  : PrimaryButton(
                      label: primaryLabel!,
                      onPressed: onPrimary,
                      loading: primaryLoading,
                    ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: Space.x2),
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: c.muted,
                  minimumSize: const Size(Sizes.tap, Sizes.tap),
                ),
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initial,
  });

  final String title;
  final String hint;
  final String? initial;
  final String confirmLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      primaryLabel: widget.confirmLabel,
      onPrimary: _submit,
      secondaryLabel: context.l10n.commonCancel,
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}
