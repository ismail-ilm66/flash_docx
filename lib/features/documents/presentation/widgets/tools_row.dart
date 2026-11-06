import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// One Home › Tools entry.
class HomeTool {
  const HomeTool({required this.icon, required this.label, required this.onTap});

  final AppIcons icon;
  final String label;
  final VoidCallback onTap;
}

/// Home › Tools (round 4, feature 1): a 2-column grid of compact tiles.
class ToolsRow extends StatelessWidget {
  const ToolsRow({required this.tools, super.key});

  final List<HomeTool> tools;

  @override
  Widget build(BuildContext context) {
    final rows = <List<HomeTool>>[
      for (var i = 0; i < tools.length; i += 2) tools.sublist(i, (i + 2).clamp(0, tools.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.homeTools, style: context.text.titleLarge?.copyWith(fontSize: 17)),
        const SizedBox(height: 10),
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ToolTile(tool: row[0])),
              const SizedBox(width: 10),
              Expanded(child: row.length > 1 ? _ToolTile(tool: row[1]) : const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final HomeTool tool;

  static final _radius = BorderRadius.circular(14);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: tool.label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: _radius, side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tool.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Space.x2),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: AppIcon(tool.icon, size: 18, color: c.accentText),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FitText(
                      tool.label,
                      textAlign: TextAlign.start,
                      style: context.text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
