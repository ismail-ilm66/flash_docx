import 'dart:async';

import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// "Continue your last scan · 8 pages" (round 7, P0-3): a scan the app was
/// closed, killed or crashed on. Shown on Home until it's continued or
/// discarded.
class DraftCard extends StatelessWidget {
  const DraftCard({required this.drafts, super.key});

  final DraftService drafts;

  Future<void> _continue(BuildContext context) async {
    final d = drafts.takePending();
    if (d == null) return;
    await context.push(Routes.adjust, extra: EditorArgs(pages: d.pages, mode: d.mode));
  }

  Future<void> _discard(BuildContext context, int count) async {
    if (await confirmDiscardScan(context, count)) unawaited(drafts.discard());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScanDraft?>(
      valueListenable: drafts.pending,
      builder: (context, draft, _) {
        if (draft == null) return const SizedBox.shrink();
        final c = context.colors;
        final l = context.l10n;
        final n = draft.pages.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.x5),
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x2, Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: AppIcon(AppIcons.document, size: 18, color: c.accentText),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${l.homeDraftTitle} · ${l.pagesCount(n)}',
                          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.x1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _discard(context, n),
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        child: Text(l.discardScan),
                      ),
                      const SizedBox(width: Space.x1),
                      PrimaryButton(
                        label: l.homeDraftContinue,
                        expand: false,
                        dense: true,
                        onPressed: () => _continue(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
