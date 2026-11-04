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

class _PrintView extends StatefulWidget {
  const _PrintView();

  @override
  State<_PrintView> createState() => _PrintViewState();
}

class _PrintViewState extends State<_PrintView> {
  /// Which sheet of the layout is previewed (duplex: fronts, backs).
  int _sheet = 0;

  Future<void> _pickCopies(BuildContext context, int n) async {
    final cubit = context.read<PrintLayoutCubit>();
    if (cubit.state.copiesGated(n)) {
      final ok = await showUnlockDialog(context, PremiumFeature.moreCopies);
      if (!ok) return;
      cubit.unlockMoreCopies();
    }
    cubit.setCopies(n);
  }

  static String _mm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PrintLayoutCubit, PrintLayoutState>(
      listenWhen: (a, b) => a.status != b.status || a.output != b.output,
      listener: (context, s) {
        final st = s.status;
        if (st is PrintDone && st.target == ExportTarget.saveToPhone) context.showSnack(l.shareSaved);
        if (st is PrintFailed) context.showSnack(failureMessage(context, st.failure), error: true);
        setState(() => _sheet = 0);
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
        final layout = PrintLayoutCalculator.layout(spec);
        final sheets = layout.pages.length;
        final sheet = _sheet.clamp(0, sheets - 1);
        final card = PrintLayoutCalculator.cardSize(kind);
        final pages = doc.sortedPages;
        final duplex = s.output == PrintOutput.pdfDoubleSided && sheets > 1;
        final scale = l.printTipScale;
        final flip = l.printTipFlip;

        return AppScaffold(
          topBar: AppTopBar(title: l.printTitle, subtitle: doc.title),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.allowedOutputs.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  child: SegmentedPills<PrintOutput>(
                    values: s.allowedOutputs,
                    selected: s.output,
                    height: 44,
                    labelSize: 12,
                    labelOf: (o) => switch (o) {
                      PrintOutput.image => l.printOutputImage,
                      PrintOutput.pdfDoubleSided => l.printOutputDoubleSided,
                      PrintOutput.pdfOnePage => l.printOutputOnePage,
                    },
                    onChanged: cubit.setOutput,
                  ),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: Space.x3),
                  color: c.stage,
                  padding: const EdgeInsets.symmetric(vertical: Space.x3),
                  child: Column(
                    children: [
                      if (sheets > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < sheets; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              _SheetChip(
                                label: duplex
                                    ? (i.isEven ? l.printSheetFronts(i + 1) : l.printSheetBacks(i + 1))
                                    : l.pageOfTotal(i + 1, sheets),
                                selected: i == sheet,
                                onTap: () => setState(() => _sheet = i),
                              ),
                            ],
                          ],
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x3),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: PrintLayoutCalculator.sheetW / PrintLayoutCalculator.sheetH,
                              child: _SheetPreview(
                                items: layout.pages[sheet],
                                frontPath: pages.first.thumbPath ?? pages.first.displayPath,
                                backPath: pages.length > 1 ? (pages[1].thumbPath ?? pages[1].displayPath) : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        l.printSheetCaption(_mm(card.w), _mm(card.h)),
                        style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(l.printCopies, padding: const EdgeInsets.only(bottom: Space.x2)),
                    Row(
                      children: [
                        for (final (i, n) in s.allowedCopies.indexed) ...[
                          if (i > 0) const SizedBox(width: Space.x2),
                          Expanded(
                            child: _CopiesButton(
                              n: n,
                              selected: s.copies == n,
                              locked: s.copiesGated(n),
                              onTap: () => _pickCopies(context, n),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.x3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 10),
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: AppIcon(AppIcons.print, size: 20, color: c.accentText),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BoldParts(
                              text: s.output == PrintOutput.pdfDoubleSided
                                  ? l.printTipDuplex(flip, scale)
                                  : l.printTipSingle(scale),
                              bold: [flip, scale],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: l.shareSaveToPhone,
                          dense: true,
                          onPressed: working ? null : () => cubit.run(ExportTarget.saveToPhone),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: s.output == PrintOutput.image ? l.printShareImage : l.shareButtonFormat(l.sharePdf),
                          loading: working,
                          onPressed: () => cubit.run(ExportTarget.share),
                        ),
                      ),
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

/// Renders [text] with each occurrence of the strings in [bold] in bold.
class _BoldParts extends StatelessWidget {
  const _BoldParts({required this.text, required this.bold});

  final String text;
  final List<String> bold;

  @override
  Widget build(BuildContext context) {
    final base = context.text.bodySmall?.copyWith(height: 1.45, color: context.colors.text);
    final spans = <TextSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var at = -1;
      var hit = '';
      for (final b in bold) {
        final i = b.isEmpty ? -1 : rest.indexOf(b);
        if (i >= 0 && (at < 0 || i < at)) {
          at = i;
          hit = b;
        }
      }
      if (at < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      spans.add(TextSpan(text: hit, style: const TextStyle(fontWeight: FontWeight.w800)));
      rest = rest.substring(at + hit.length);
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pillR,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.text : Colors.transparent,
            borderRadius: Radii.pillR,
            border: Border.all(color: selected ? c.text : c.borderStrong),
          ),
          child: Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: selected ? (c.isDark ? c.bg : c.surface) : c.text,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CopiesButton extends StatelessWidget {
  const _CopiesButton({required this.n, required this.selected, required this.locked, required this.onTap});

  final int n;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '$n, ${context.l10n.unlockTitle}' : '$n',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: Motion.normal,
              height: Sizes.tap,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: selected ? Border.all(color: c.accent, width: 2) : Border.all(color: c.borderStrong),
              ),
              child: Text('$n', style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (locked)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: AppIcon(AppIcons.play, size: 9, color: c.onAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Scaled-down drawing of one sheet, using page thumbnails.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({required this.items, required this.frontPath, this.backPath});
  final List<PlacedItem> items;
  final String frontPath;
  final String? backPath;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final k = box.maxWidth / PrintLayoutCalculator.sheetW;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 22, offset: Offset(0, 6))],
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
                    child: PageImage(
                      path: it.isBack ? (backPath ?? frontPath) : frontPath,
                      radius: 3,
                      cacheWidth: 240,
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
