import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell around the two tabs: Home · centre scan button · Settings.
/// The active tab is derived from the shell's branch index, so it always
/// matches the current route.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: shell,
      extendBody: true,
      bottomNavigationBar: AppBottomNav(
        index: shell.currentIndex,
        onTab: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        onScan: () => context.push(Routes.camera),
      ),
    );
  }
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.index,
    required this.onTab,
    required this.onScan,
    super.key,
  });

  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Sizes.navBar,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: AppIcons.home,
                  label: l.navHome,
                  active: index == 0,
                  onTap: () => onTab(0),
                ),
              ),
              ScanFab(onPressed: onScan),
              Expanded(
                child: _NavItem(
                  icon: AppIcons.settings,
                  label: l.navSettings,
                  active: index == 1,
                  onTap: () => onTab(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accentText : c.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: context.text.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class ScanFab extends StatelessWidget {
  const ScanFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.navScan,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        child: Material(
          color: c.accent,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: c.accent.withValues(alpha: 0.4),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: AppIcon(AppIcons.camera, color: c.onAccent, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
