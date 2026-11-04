import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

/// Standard bottom sheet with a drag handle, optional title and padded body.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    required this.child,
    super.key,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(Space.x5, 0, Space.x5, 22),
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsets padding;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      // Above the shell's bottom nav, not inside the tab's navigator.
      useRootNavigator: true,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: Space.x4),
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: Radii.pillR,
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, 0, Space.x5, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: context.text.bodyMedium?.copyWith(fontSize: 13, color: c.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: padding,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple list item for action sheets (⋮ menus).
class SheetAction extends StatelessWidget {
  const SheetAction({
    required this.label,
    required this.onTap,
    super.key,
    this.leading,
    this.destructive = false,
    this.selected = false,
  });

  final String label;
  final Widget? leading;
  final VoidCallback onTap;
  final bool destructive;

  /// Shows a trailing check (single-choice pickers).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? c.danger : c.text;
    return ListTile(
      onTap: onTap,
      leading: leading == null
          ? null
          : IconTheme(data: IconThemeData(color: color), child: leading!),
      title: Text(label, style: context.text.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
      trailing: selected ? AppIcon(AppIcons.check, size: 20, color: c.accentText) : null,
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.x3),
      shape: RoundedRectangleBorder(borderRadius: Radii.mdR),
      minTileHeight: Sizes.tap + 4,
    );
  }
}

/// Bottom sheet listing [values]; resolves the one tapped, or null.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T selected,
  required String Function(T) labelOf,
  Widget? Function(T)? badgeOf,
}) {
  return AppBottomSheet.show<T>(
    context,
    builder: (ctx) => AppBottomSheet(
      title: title,
      padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x4),
      child: Column(
        children: [
          for (final v in values)
            SheetAction(
              label: labelOf(v),
              selected: v == selected,
              leading: badgeOf?.call(v),
              onTap: () => Navigator.of(ctx).pop(v),
            ),
        ],
      ),
    ),
  );
}
