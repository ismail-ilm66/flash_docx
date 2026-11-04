import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppIcons? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      color: c.onAccent,
    );
    final btn = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.accent.withValues(alpha: 0.4),
        disabledForegroundColor: c.onAccent.withValues(alpha: 0.6),
        minimumSize: const Size(Sizes.tap, 52),
        padding: const EdgeInsets.symmetric(horizontal: Space.x5),
        shape: RoundedRectangleBorder(borderRadius: Radii.mdR),
        textStyle: context.text.labelLarge,
      ),
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppIcons? icon;
  final bool loading;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = destructive ? c.danger : c.text;
    final btn = OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: c.surface,
        side: BorderSide(color: c.border),
        minimumSize: const Size(Sizes.tap, 52),
        padding: const EdgeInsets.symmetric(horizontal: Space.x5),
        shape: RoundedRectangleBorder(borderRadius: Radii.mdR),
        textStyle: context.text.labelLarge,
      ),
      child: _ButtonContent(label: label, icon: icon, loading: loading, color: fg),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.loading,
    required this.color,
    this.icon,
  });

  final String label;
  final AppIcons? icon;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: Sizes.iconSm, color: color),
          const SizedBox(width: Space.x2),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Icon + label, used on the Adjust edges and Viewer toolbars.
class ToolbarAction extends StatelessWidget {
  const ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.active = false,
    this.destructive = false,
  });

  final AppIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final color = !enabled
        ? c.muted.withValues(alpha: 0.5)
        : destructive
            ? c.danger
            : active
                ? c.accentText
                : c.text;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: Radii.mdR,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: Sizes.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x2,
              vertical: Space.x2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, color: color),
                const SizedBox(height: Space.x1),
                Text(
                  label,
                  style: context.text.labelSmall?.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
