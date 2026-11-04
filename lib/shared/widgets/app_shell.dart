import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/back_guards.dart';
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
    return LeaveAppGuard(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: shell,
        bottomNavigationBar: AppBottomNav(
          index: shell.currentIndex,
          onTab: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          onScan: () => context.push(Routes.camera),
        ),
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
    return DecoratedBox(
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
              Expanded(
                child: Center(child: ScanFab(onPressed: onScan)),
              ),
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
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.normal,
              curve: Curves.easeOutCubic,
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: active ? c.accentSoft : Colors.transparent,
                borderRadius: Radii.pillR,
              ),
              alignment: Alignment.center,
              child: AppIcon(
                icon,
                size: 22,
                color: active ? c.accentText : c.muted,
              ),
            ),
            const SizedBox(height: Space.x1),
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: active ? c.text : c.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised centre scan button: 64 px accent circle ringed in the page
/// background so it reads as cut out of the bar.
class ScanFab extends StatelessWidget {
  const ScanFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.navScan,
      excludeSemantics: true,
      child: Transform.translate(
        offset: const Offset(0, -20),
        child: Container(
          width: Sizes.fab,
          height: Sizes.fab,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.bg, width: 5),
          ),
          child: Material(
            color: c.accent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: AppIcon(AppIcons.camera, color: c.onAccent, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
