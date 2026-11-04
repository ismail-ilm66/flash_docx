import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Page indicator: the current page is a wide accent pill. Each dot is a
/// 44 px tap target that jumps to its page.
class PageDots extends StatelessWidget {
  const PageDots({
    required this.count,
    required this.index,
    super.key,
    this.onSelect,
  });

  final int count;
  final int index;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: onSelect != null,
            selected: i == index,
            label: l.pageOfTotal(i + 1, count),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect == null ? null : () => onSelect!(i),
              child: SizedBox(
                height: Sizes.tap,
                width: count > 8 ? 18 : 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: Motion.normal,
                    curve: Curves.easeOutCubic,
                    width: i == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == index ? c.accent : const Color(0xFF4A4E56),
                      borderRadius: Radii.pillR,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
