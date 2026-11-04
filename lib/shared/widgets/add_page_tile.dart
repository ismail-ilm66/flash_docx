import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/dashed_border.dart';
import 'package:flutter/material.dart';

/// Dashed "+" tile at the end of a page strip.
class AddPageTile extends StatelessWidget {
  const AddPageTile({required this.onTap, super.key, this.size = 52});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.viewerAddPages,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DashedBorder(
          color: c.borderStrong,
          child: SizedBox(
            width: size,
            height: size * 68 / 52,
            child: Center(child: AppIcon(AppIcons.addPage, size: 22, color: c.muted)),
          ),
        ),
      ),
    );
  }
}
