import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Standard bottom sheet with a drag handle, optional title and padded body.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    required this.child,
    super.key,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
  });

  final String? title;
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
                margin: const EdgeInsets.only(top: Space.x3, bottom: Space.x3),
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: Radii.pillR,
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
                child: Text(title!, style: context.text.titleLarge),
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
  });

  final String label;
  final Widget? leading;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? c.danger : c.text;
    return ListTile(
      onTap: onTap,
      leading: leading == null
          ? null
          : IconTheme(data: IconThemeData(color: color), child: leading!),
      title: Text(label, style: context.text.bodyLarge?.copyWith(color: color)),
      shape: RoundedRectangleBorder(borderRadius: Radii.mdR),
      minTileHeight: Sizes.tap + 4,
    );
  }
}
