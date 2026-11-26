import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

/// Home's floating camera button (round 11): round, 64 dp, amber, at the
/// bottom right within thumb reach; opens the camera in Document mode.
class ScanFab extends StatelessWidget {
  const ScanFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.navScan,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Material(
        color: c.accent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: AppIcon(AppIcons.camera, color: c.onAccent, size: 28)),
          ),
        ),
      ),
      ),
    );
  }
}
