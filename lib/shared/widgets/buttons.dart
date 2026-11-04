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
    this.height = 52,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppIcons? icon;
  final bool loading;
  final bool expand;
  final double height;

  /// Tighter padding and 14 px label, for three buttons in a row.
  final bool dense;

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
        minimumSize: Size(Sizes.tap, height),
        padding: EdgeInsets.symmetric(horizontal: dense ? Space.x2 : Space.x5),
        shape: const StadiumBorder(),
        textStyle: context.text.labelLarge?.copyWith(fontSize: dense ? 14 : 15, fontWeight: FontWeight.w800),
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
    this.height = 52,
    this.filled = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppIcons? icon;
  final bool loading;
  final bool expand;
  final bool destructive;
  final double height;

  /// Surface fill instead of transparent (used over the page background).
  final bool filled;

  /// Tighter padding and 14 px label, for three buttons in a row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = destructive ? c.danger : c.text;
    final btn = OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: filled ? c.surface : Colors.transparent,
        side: BorderSide(color: c.borderStrong),
        minimumSize: Size(Sizes.tap, height),
        padding: EdgeInsets.symmetric(horizontal: dense ? Space.x2 : Space.x4),
        shape: const StadiumBorder(),
        textStyle: context.text.labelLarge?.copyWith(fontSize: dense ? 14 : 15),
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
          AppIcon(icon!, size: 18, color: color),
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
    this.iconSize = Sizes.icon,
  });

  final AppIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool destructive;
  final double iconSize;

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
          constraints: const BoxConstraints(minWidth: 56, minHeight: Sizes.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x1,
              vertical: Space.x2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: iconSize, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
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

/// Accent text action for a top bar ("Next", "Done").
class TopBarTextAction extends StatelessWidget {
  const TopBarTextAction({
    required this.label,
    required this.onPressed,
    super.key,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: c.accentText),
        ),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        disabledForegroundColor: c.muted,
        minimumSize: const Size(Sizes.tap, Sizes.tap),
        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
        textStyle: context.text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}
