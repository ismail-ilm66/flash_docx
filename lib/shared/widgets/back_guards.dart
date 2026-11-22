import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Leave Flash Dox?" on the root screen (Android back on Home).
class LeaveAppGuard extends StatelessWidget {
  const LeaveAppGuard({required this.child, super.key});

  final Widget child;

  /// Set while a screen in the shell has its own use for Back (Home's
  /// selection mode, round 10 P1-5): Back calls it instead of asking.
  static VoidCallback? interceptor;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final intercept = interceptor;
        if (intercept != null) return intercept();
        final l = context.l10n;
        final leave = await AppDialog.confirm(
          context,
          title: l.backLeaveTitle,
          body: '',
          confirmLabel: l.backLeave,
          cancelLabel: l.backStay,
        );
        if (leave) await SystemNavigator.pop();
      },
      child: child,
    );
  }
}

/// "Discard 8 scans?" · Discard (red) · Keep editing (round 7, P0-3).
/// Resolves true to discard; tapping outside keeps the scan.
Future<bool> confirmDiscardScan(BuildContext context, int pageCount) {
  final l = context.l10n;
  return AppDialog.confirm(
    context,
    title: l.discardScanTitle(pageCount),
    body: '',
    confirmLabel: l.discardScan,
    cancelLabel: l.keepEditing,
    destructive: true,
  );
}

/// Wraps a screen that holds an unsaved scan. Back (Android), ✕ and the
/// iOS swipe all go through [onDiscard]; when [guard] is false the
/// screen pops normally.
class DiscardScanGuard extends StatelessWidget {
  const DiscardScanGuard({
    required this.guard,
    required this.pageCount,
    required this.onDiscard,
    required this.child,
    super.key,
  });

  final bool guard;
  final int pageCount;
  final VoidCallback onDiscard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !guard,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardScan(context, pageCount)) onDiscard();
      },
      child: child,
    );
  }
}
