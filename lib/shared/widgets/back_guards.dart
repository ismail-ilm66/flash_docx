import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Leave Flash Dox?" on the root screen (Android back on Home).
class LeaveAppGuard extends StatelessWidget {
  const LeaveAppGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
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

/// "Discard this scan? N pages will be lost." Resolves true to discard.
Future<bool> confirmDiscardScan(BuildContext context, int pageCount) {
  final l = context.l10n;
  return AppDialog.confirm(
    context,
    title: l.discardScanTitle,
    body: l.discardScanBody(pageCount),
    confirmLabel: l.discardScan,
    cancelLabel: l.keepScanning,
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
