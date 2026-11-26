import 'dart:io';

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
import 'package:flash_dox/shared/widgets/zoomable_pages.dart';
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

  /// Round 10, P1-3: how much of the width one sheet takes.
  static const _peek = 0.85;
  final PageController _pageCtrl = PageController(viewportFraction: _peek);

  void _goSheet(int i) {
    setState(() => _sheet = i);
    if (_pageCtrl.hasClients) {
      _pageCtrl.animateToPage(
        i,
        duration: Motion.normal,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCopies(BuildContext context, int n) async {
    final cubit = context.read<PrintLayoutCubit>();
    if (cubit.state.copiesGated(n)) {
      final ok = await showUnlockDialog(context, PremiumFeature.moreCopies);
      if (!ok) return;
      cubit.unlockMoreCopies();
    }
    cubit.setCopies(n);
  }

  static String _mm(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PrintLayoutCubit, PrintLayoutState>(
      listenWhen: (a, b) => a.status != b.status || a.output != b.output,
      listener: (context, s) {
        final st = s.status;
        if (st is PrintDone && st.target == ExportTarget.saveToPhone) {
          showSaved(context);
        }
        if (st is PrintFailed) {
          context.showSnack(failureMessage(context, st.failure), error: true);
        }
        setState(() => _sheet = 0);
      },
      builder: (context, s) {
        final cubit = context.read<PrintLayoutCubit>();
        final doc = s.document;
        final kind = s.kind;
        if (doc == null) {
          return AppScaffold(
            topBar: AppTopBar(title: l.printTitle),
            body: s.failure == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorView(failure: s.failure),
          );
        }
        if (kind == null) {
          return AppScaffold(
            topBar: AppTopBar(title: l.printTitle),
            body: EmptyState(title: l.printNotAvailable),
          );
        }
        final working = s.status is PrintWorking;
        final spec = PrintLayoutSpec(
          kind: kind,
          output: s.output,
          copies: s.copies,
          frontPath: '',
          backPath: s.hasBack ? '' : null,
          cutGuides: s.cutGuides,
        );
        final layout = PrintLayoutCalculator.layout(spec);
        final sheets = layout.pages.length;
        final duplex = s.output == PrintOutput.pdfDoubleSided && sheets > 1;
        final page = PrintLayoutCalculator.pageSize(spec);
        final sheet = _sheet.clamp(0, sheets - 1);
        final card = PrintLayoutCalculator.cardSize(kind);
        final pages = doc.sortedPages;
        final frontPage = s.swapSides && pages.length > 1
            ? pages[1]
            : pages.first;
        final backPage = pages.length > 1
            ? (s.swapSides ? pages.first : pages[1])
            : null;
        final scale = l.printTipScale;
        final flip = l.printTipFlip;

        Widget sheetAt(int i) => AspectRatio(
          aspectRatio: page.w / page.h,
          child: _SheetPreview(
            pageWidth: page.w,
            items: layout.pages[i],
            cutGuides: s.cutGuides && s.output != PrintOutput.image,
            // The real cards, rendered as they print.
            frontPath: s.previews[frontPage.id],
            backPath: backPage == null ? null : s.previews[backPage.id],
          ),
        );
        // Round 10, P1-3: a title, not buttons: which sheet, what's on it and
        // when to print it.
        final title = sheets <= 1
            ? null
            : duplex
            ? (sheet.isEven ? l.printSheetTitleFronts(sheet + 1, sheets) : l.printSheetTitleBacks(sheet + 1, sheets, sheet))
            : l.printSheetOf(sheet + 1, sheets);
        // Each sheet 85 % of the full width (24 dp margins), so the next one
        // peeks in.
        final previewWidth = MediaQuery.sizeOf(context).width - 2 * Space.x6;
        final previewHeight = previewWidth * _peek * page.h / page.w;

        return AppScaffold(
          topBar: AppTopBar(title: l.printTitle, subtitle: doc.title),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
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
                      Container(
                        margin: const EdgeInsets.only(top: Space.x3),
                        color: c.stage,
                        padding: const EdgeInsets.symmetric(vertical: Space.x3),
                        child: Column(
                          children: [
                            if (title != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.x6),
                              child: SizedBox(
                                height: previewHeight + 2 * Space.x2,
                                child: PageView.builder(
                                  controller: _pageCtrl,
                                  itemCount: sheets,
                                  onPageChanged: (i) => setState(() => _sheet = i),
                                  itemBuilder: (context, i) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x2),
                                    child: Center(
                                      // Tap: full screen, pinch to zoom.
                                      child: GestureDetector(
                                        onTap: () => _openFullScreen(context, sheets, i, sheetAt),
                                        child: sheetAt(i),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (sheets > 1) ...[
                              const SizedBox(height: Space.x2),
                              _Dots(count: sheets, index: sheet, onTap: _goSheet),
                            ],
                            const SizedBox(height: Space.x2),
                            Text(
                              s.output == PrintOutput.image
                                  ? l.printImageCaption(_mm(page.w), _mm(page.h))
                                  : l.printSheetCaption(_mm(card.w), _mm(card.h)),
                              style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (s.output != PrintOutput.image) ...[
                              SectionLabel(l.printCopies, padding: const EdgeInsets.only(bottom: Space.x2)),
                              Row(
                                children: [
                                  for (final (i, n) in s.allowedCopies.indexed) ...[
                                    if (i > 0) const SizedBox(width: Space.x2),
                                    Expanded(
                                      child: _ChoiceButton(
                                        label: '$n',
                                        selected: s.copies == n,
                                        locked: s.copiesGated(n),
                                        onTap: () => _pickCopies(context, n),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: Space.x3),
                              Row(
                                children: [
                                  Switch.adaptive(value: s.cutGuides, onChanged: cubit.setCutGuides),
                                  const SizedBox(width: Space.x1),
                                  Flexible(child: Text(l.printCutGuides, style: context.text.labelMedium)),
                                ],
                              ),
                            ],
                            // Round 10, P1-4: a real button on its own row (it
                            // doesn't fit beside Cut guides at 360 dp).
                            if (s.hasBack) ...[
                              const SizedBox(height: Space.x2),
                              _SwapButton(label: l.printSwapSides, onTap: cubit.toggleSwapSides),
                              const SizedBox(height: Space.x1),
                              Text(l.printSwapHint, style: context.text.labelSmall?.copyWith(color: c.muted)),
                            ],
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
                                      text: s.output == PrintOutput.pdfDoubleSided ? l.printTipDuplex(flip, scale) : l.printTipSingle(scale),
                                      bold: [flip, scale],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Space.x3),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          onPressed: working
                              ? null
                              : () async {
                                  if (await readyToSave(context)) await cubit.run(ExportTarget.saveToPhone);
                                },
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

  /// Round 10, P1-3: a sheet full screen, pinch to zoom, swipe between
  /// sheets.
  void _openFullScreen(BuildContext context, int count, int index, Widget Function(int) sheetAt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => AppScaffold(
          backgroundColor: context.colors.stage,
          topBar: AppTopBar(title: context.l10n.printTitle, leading: TopBarLeading.close),
          body: ZoomablePages(
            controller: PageController(initialPage: index),
            itemCount: count,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Center(child: sheetAt(i)),
            ),
          ),
        ),
      ),
    ).ignore();
  }
}

/// Page dots under the sheets: the shown one is a wide amber pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: Motion.fast,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == index ? c.accent : c.border, borderRadius: Radii.pillR),
            ),
          ),
      ],
    );
  }
}

/// "⇅ Swap front & back" (round 10, P1-4): outlined in amber, dark text in
/// the light theme, light text in the dark theme.
class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF3F3F1) : const Color(0xFF1B1B1B);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: AppIcon(AppIcons.reorder, size: 18, color: ink),
        label: Text(label, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: ink)),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: c.accent, width: 1.5),
          minimumSize: const Size(0, Sizes.tap),
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
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
    final base = context.text.bodySmall?.copyWith(
      height: 1.45,
      color: context.colors.text,
    );
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
      spans.add(
        TextSpan(
          text: hit,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
      rest = rest.substring(at + hit.length);
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// A square-cornered choice (copies, quality), artboard *Print layout*.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '$label, ${context.l10n.unlockTitle}' : label,
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
                border: selected
                    ? Border.all(color: c.accent, width: 2)
                    : Border.all(color: c.borderStrong),
              ),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              child: FitText(
                label,
                maxLines: 1,
                style: context.text.titleSmall?.copyWith(
                  fontSize: label.length > 3 ? 13 : 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (locked)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
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
  const _SheetPreview({
    required this.pageWidth,
    required this.items,
    required this.frontPath,
    this.backPath,
    this.cutGuides = false,
  });

  /// Millimetres across: A4 for the PDFs, the tight image otherwise.
  final double pageWidth;
  final List<PlacedItem> items;
  final String? frontPath;
  final String? backPath;
  final bool cutGuides;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final k = box.maxWidth / pageWidth;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 22,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (cutGuides)
                Positioned.fill(
                  child: CustomPaint(painter: _CropMarksPainter(items, k)),
                ),
              for (final it in items)
                Positioned(
                  left: it.x * k,
                  top: it.y * k,
                  width: it.w * k,
                  height: it.h * k,
                  child: RotatedBox(
                    quarterTurns: it.rotated ? 3 : 0,
                    child: _CardImage(path: it.isBack ? (backPath ?? frontPath) : frontPath),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CropMarksPainter extends CustomPainter {
  _CropMarksPainter(this.items, this.k);
  final List<PlacedItem> items;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = 1;
    for (final ((x1, y1), (x2, y2)) in PrintLayoutCalculator.cropMarks(items)) {
      canvas.drawLine(Offset(x1 * k, y1 * k), Offset(x2 * k, y2 * k), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropMarksPainter old) =>
      old.items != items || old.k != k;
}

/// One card on the preview sheet: the rendered card, or a quiet loading
/// state while it renders (never a template card).
class _CardImage extends StatelessWidget {
  const _CardImage({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: p == null
          ? const ColoredBox(
              color: Color(0xFFE9EEF2),
              child: Center(
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFF9AA6B2))),
              ),
            )
          : Image.file(File(p), fit: BoxFit.fill, gaplessPlayback: true, cacheWidth: 600),
    );
  }
}
