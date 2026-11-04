import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Top bar: back/close + title + subtitle + actions.
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
  });

  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final List<Widget> actions;
  final TopBarLeading leading;
  final VoidCallback? onLeading;
  final bool transparent;

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
        ),
      );
    }
    return AppBar(
      backgroundColor: transparent ? Colors.transparent : c.bg,
      leading: lead,
      automaticallyImplyLeading: false,
      titleSpacing: lead == null ? Space.x4 : 0,
      title: titleWidget ??
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: context.text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.text.bodySmall?.copyWith(color: c.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
      actions: [...actions, const SizedBox(width: Space.x2)],
    );
  }
}

enum TopBarLeading { back, close, none }
