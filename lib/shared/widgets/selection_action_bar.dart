import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flash_dox/shared/widgets/fit_text.dart';
import 'package:flutter/material.dart';

/// One button of a [SelectionActionBar].
class SelectionAction {
  const SelectionAction(this.icon, this.label, this.onTap, {this.danger = false});
  final AppIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The bottom bar of a selection mode (round 11: Home P0-1, viewer pages
/// P0-13): icon + one-line label buttons, 76 dp tall above the safe area.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({required this.actions, this.enabled = true, super.key});

  final List<SelectionAction> actions;
  final bool enabled;

  static const double height = 76;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final a in actions)
                Expanded(
                  child: InkWell(
                    onTap: enabled ? a.onTap : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(a.icon, size: 22, color: !enabled ? c.muted : a.danger ? c.danger : c.text),
                        const SizedBox(height: 4),
                        FitText(
                          a.label,
                          maxLines: 1,
                          style: context.text.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: !enabled ? c.muted : a.danger ? c.danger : c.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
