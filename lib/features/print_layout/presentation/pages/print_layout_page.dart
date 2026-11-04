import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/features/print_layout/presentation/cubit/print_layout_cubit.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/rewards/presentation/unlock_dialog.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PrintLayoutPage extends StatelessWidget {
  const PrintLayoutPage({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    getIt<RewardGate>().preload();
    return BlocProvider(
      create: (_) => getIt<PrintLayoutCubit>(param1: documentId),
      child: const _PrintView(),
    );
  }
}

class _PrintView extends StatelessWidget {
  const _PrintView();

  Future<void> _pickCopies(BuildContext context, int n) async {
    final cubit = context.read<PrintLayoutCubit>();
    if (cubit.state.copiesGated(n)) {
      final ok = await showUnlockDialog(context, PremiumFeature.moreCopies);
      if (!ok) return;
      cubit.unlockMoreCopies();
    }
    cubit.setCopies(n);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PrintLayoutCubit, PrintLayoutState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        final st = s.status;
        if (st is PrintDone && st.target == ExportTarget.saveToPhone) context.showSnack(l.shareSaved);
        if (st is PrintFailed) context.showSnack(failureMessage(context, st.failure), error: true);
      },
      builder: (context, s) {
        final cubit = context.read<PrintLayoutCubit>();
        final doc = s.document;
        final kind = s.kind;
        if (doc == null) {
          return AppScaffold(
            topBar: AppTopBar(title: l.printTitle),
            body: s.failure == null ? const Center(child: CircularProgressIndicator()) : ErrorView(failure: s.failure),
          );
        }
        if (kind == null) {
          return AppScaffold(topBar: AppTopBar(title: l.printTitle), body: EmptyState(title: l.printNotAvailable));
        }
        final working = s.status is PrintWorking;
        final spec = PrintLayoutSpec(
          kind: kind,
          output: s.output,
          copies: s.copies,
          frontPath: '',
          backPath: doc.pages.length > 1 ? '' : null,
        );
        return AppScaffold(
          topBar: AppTopBar(title: l.printTitle, subtitle: doc.title),
          body: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(Space.x4),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: PrintLayoutCalculator.sheetW / PrintLayoutCalculator.sheetH,
                      child: _SheetPreview(spec: spec, frontPath: doc.sortedPages.first.thumbPath ?? doc.sortedPages.first.displayPath, backPath: doc.pages.length > 1 ? (doc.sortedPages[1].thumbPath ?? doc.sortedPages[1].displayPath) : null),
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 0),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.printOutput, style: context.text.labelMedium?.copyWith(color: c.muted)),
                      const SizedBox(height: Space.x2),
                      SegmentedPills<PrintOutput>(
                        values: s.allowedOutputs,
                        selected: s.output,
                        labelOf: (o) => switch (o) {
                          PrintOutput.image => l.printOutputImage,
                          PrintOutput.pdfDoubleSided => l.printOutputDoubleSided,
                          PrintOutput.pdfOnePage => l.printOutputOnePage,
                        },
                        onChanged: cubit.setOutput,
                      ),
                      const SizedBox(height: Space.x4),
                      Text(l.printCopies, style: context.text.labelMedium?.copyWith(color: c.muted)),
                      const SizedBox(height: Space.x2),
                      Wrap(
                        spacing: Space.x2,
                        runSpacing: Space.x2,
                        children: [
                          for (final n in s.allowedCopies)
                            OptionChip(
                              label: '$n',
                              selected: s.copies == n,
                              gated: s.copiesGated(n),
                              onTap: () => _pickCopies(context, n),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.x3),
                      Row(
                        children: [
                          AppIcon(AppIcons.info, size: 16, color: c.muted),
                          const SizedBox(width: Space.x2),
                          Expanded(child: Text(l.printActualSize, style: context.text.bodySmall?.copyWith(color: c.muted))),
                        ],
                      ),
                      const SizedBox(height: Space.x4),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              label: l.printSave,
                              icon: AppIcons.save,
                              onPressed: working ? null : () => cubit.run(ExportTarget.saveToPhone),
                            ),
                          ),
                          const SizedBox(width: Space.x3),
                          Expanded(
                            child: PrimaryButton(
                              label: l.printShare,
                              icon: AppIcons.share,
                              loading: working,
                              onPressed: () => cubit.run(ExportTarget.share),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.x4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Scaled-down drawing of the first sheet, using page thumbnails.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({required this.spec, required this.frontPath, this.backPath});
  final PrintLayoutSpec spec;
  final String frontPath;
  final String? backPath;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layout = PrintLayoutCalculator.layout(spec);
    final items = layout.pages.first;
    return LayoutBuilder(
      builder: (context, box) {
        final k = box.maxWidth / PrintLayoutCalculator.sheetW;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              for (final it in items)
                Positioned(
                  left: it.x * k,
                  top: it.y * k,
                  width: it.w * k,
                  height: it.h * k,
                  child: RotatedBox(
                    quarterTurns: it.rotated ? 3 : 0,
                    child: PageThumb(
                      path: it.isBack ? (backPath ?? frontPath) : frontPath,
                      size: (it.rotated ? it.h : it.w) * k,
                      aspect: (it.rotated ? it.h : it.w) / (it.rotated ? it.w : it.h),
                    ),
                  ),
                ),
              if (layout.pages.length > 1)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: c.accent, borderRadius: Radii.pillR),
                    child: Text('1/${layout.pages.length}', style: context.text.labelSmall?.copyWith(color: c.onAccent)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
