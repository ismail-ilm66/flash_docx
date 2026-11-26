import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android back on Home (round 11 standing rule): "Press back again to
/// exit" for 2 s; a second Back within that time leaves the app.
class LeaveAppGuard extends StatelessWidget {
  const LeaveAppGuard({required this.child, super.key});

  final Widget child;

  /// Set while Home has its own use for Back (selection or search mode):
  /// Back calls it instead.
  static VoidCallback? interceptor;

  static DateTime? _lastBack;

  /// How long the second Back may wait.
  static const window = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final intercept = interceptor;
        if (intercept != null) return intercept();
        final now = DateTime.now();
        final last = _lastBack;
        if (last != null && now.difference(last) < window) {
          _lastBack = null;
          await SystemNavigator.pop();
          return;
        }
        _lastBack = now;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.backPressAgain),
              duration: window,
              persist: false,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            ),
          );
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
