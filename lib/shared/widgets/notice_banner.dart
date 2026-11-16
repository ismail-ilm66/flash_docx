import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

/// A dark, rounded notice over a camera or photo view, with optional
/// actions (Retake / Keep…).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.text,
    required this.icon,
    this.actions = const [],
    super.key,
  });

  final String text;
  final AppIcons icon;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: const Color(0xE6202226),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.x3,
          Space.x2,
          Space.x1,
          Space.x2,
        ),
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: c.accent),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                text,
                style: context.text.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (label, onTap) in actions)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: c.accent,
                  minimumSize: const Size(Sizes.tap, Sizes.tap),
                ),
                child: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}
