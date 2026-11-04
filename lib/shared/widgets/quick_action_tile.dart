import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final AppIcons icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.lgR,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x4,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.lgR,
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: Radii.mdR,
              ),
              child: AppIcon(icon, color: c.accentText),
            ),
            const SizedBox(height: Space.x2),
            Text(
              label,
              style: context.text.labelMedium,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
