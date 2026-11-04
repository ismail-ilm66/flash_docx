import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Top bar: back/close + title + subtitle + actions. The title is centred
/// by default, as on every pushed screen of the design.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.actions = const [],
    this.leading = TopBarLeading.back,
    this.onLeading,
    this.transparent = false,
    this.centerTitle = true,
  });

  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final List<Widget> actions;
  final TopBarLeading leading;
  final VoidCallback? onLeading;
  final bool transparent;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(Sizes.topBar);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget? lead;
    if (leading != TopBarLeading.none) {
      lead = IconButton(
        tooltip: leading == TopBarLeading.back
            ? context.l10n.commonBack
            : context.l10n.commonClose,
        onPressed: onLeading ??
            () {
              if (context.canPop()) context.pop();
            },
        icon: AppIcon(
          leading == TopBarLeading.back ? AppIcons.back : AppIcons.close,
          color: c.text,
        ),
      );
    }
    final align = centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return AppBar(
      backgroundColor: transparent ? Colors.transparent : c.bg,
      toolbarHeight: Sizes.topBar,
      leading: lead == null ? null : Padding(padding: const EdgeInsets.only(left: Space.x2), child: lead),
      leadingWidth: Sizes.tap + Space.x3,
      automaticallyImplyLeading: false,
      centerTitle: centerTitle,
      titleSpacing: lead == null ? Space.x5 : Space.x1,
      title: titleWidget ??
          Column(
            crossAxisAlignment: align,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: context.text.bodySmall?.copyWith(color: c.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
      actions: [
        ...actions,
        // Keeps a centred title centred when there is a back button only.
        if (actions.isEmpty && centerTitle && lead != null) const SizedBox(width: Sizes.tap + Space.x3) else const SizedBox(width: Space.x2),
      ],
    );
  }
}

enum TopBarLeading { back, close, none }
