import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/app_router.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/storage_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flash_dox/shared/widgets/zoomable_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Enhance (round 4, P1-1, artboard *Enhance*): a big zoomable preview with
/// page dots, the zoom pill and Hold to compare; below it the six filter
/// thumbnails and Adjust · Reset · All N pages. Shares the [PageEditorBloc]
/// created by Adjust edges, so both screens are one in-memory session.
class EnhancePage extends StatelessWidget {
  const EnhancePage({required this.bloc, super.key});

  final PageEditorBloc bloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: bloc
        ..add(const EditorPreviewRequested(forEnhance: true))
        ..add(const EditorFilterThumbsRequested()),
      child: const _EnhanceView(),
    );
  }
}

class _EnhanceView extends StatefulWidget {
  const _EnhanceView();

  @override
  State<_EnhanceView> createState() => _EnhanceViewState();
}

class _EnhanceViewState extends State<_EnhanceView> {
  bool _comparing = false;
  bool _adjustOpen = false;
  // Round 11, P0-12: page 1 the first time, then where the user was.
  late int _shownIndex = context.read<PageEditorBloc>().enhanceEntry;
  final ZoomController _zoom = ZoomController();
  late final PageController _pages = PageController(
    initialPage: context.read<PageEditorBloc>().enhanceEntry,
  );

  // Local slider values so the thumb follows the finger at 60 fps; the
  // preview applies them live on the GPU.
  double? _brightness;
  double? _contrast;

  static const _stage = Color(0xFF16181B);
  static const _bar = Color(0xFF1A1C20);
  static const _outline = Color(0xFF3A3E46);

  late final PageEditorBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<PageEditorBloc>(); // for dispose
  }

  @override
  void dispose() {
    if (!_bloc.isClosed) _bloc.add(const EditorEnhanceClosed());
    _zoom.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onSaved(BuildContext context, PageEditorState s) {
    final id = s.savedDocumentId!;
    final route = routeAfterSave(isNewDocument: s.args.isNewDocument, documentId: id, tool: s.args.tool);
    if (route.goHome != null) {
      final router = GoRouter.of(context)..go(route.goHome!);
      unawaited(router.push(route.viewer!));
      final tool = route.tool;
      // Made for a tool (P1-4): open it on the new document, over its viewer.
      if (tool != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final doc = (await getIt<GetDocument>()(id)).toNullable();
          final ctx = rootNavigatorKey.currentContext;
          if (doc != null && ctx != null && ctx.mounted) await openTool(ctx, tool, doc);
        });
      }
    } else {
      // Pop Enhance and Adjust edges back to the viewer; added pages
      // (round 11, P0-11) tell it they were saved.
      context
        ..pop()
        ..pop(s.args.addingPages ? true : null);
    }
  }

  /// Round 6, P0-3: a nearly full phone may fail to save; say so (without
  /// blocking) before saving.
  Future<void> _save(PageEditorBloc bloc) async {
    final free = await getIt<StorageService>().freeBytes();
    if (!mounted) return;
    if (StorageService.levelFor(free) != StorageLevel.ok) {
      context.showSnack(context.l10n.saveStorageLow);
    }
    bloc.add(const EditorSaveRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PageEditorBloc, PageEditorState>(
      listenWhen: (a, b) => a.status != b.status || a.index != b.index,
      listener: (context, s) {
        if (s.status == EditorStatus.saved) _onSaved(context, s);
        if (s.status == EditorStatus.failed && s.failure != null) {
          context.showSnack(failureMessage(context, s.failure), error: true);
        }
        if (_shownIndex != s.index) {
          // Swiped to another page: its own thumbnails and slider values.
          _shownIndex = s.index;
          context.read<PageEditorBloc>().add(
            const EditorFilterThumbsRequested(),
          );
          setState(() {
            _brightness = null;
            _contrast = null;
          });
        }
      },
      builder: (context, s) {
        final bloc = context.read<PageEditorBloc>();
        final page = s.current;
        final edits = s.edits;
        final multi = s.pages.length > 1;
        final saving = s.status == EditorStatus.saving;
        final live = edits.copyWith(
          brightness: _brightness ?? edits.brightness,
          contrast: _contrast ?? edits.contrast,
        );

        Widget pageImage(BuildContext context, int i) {
          final p = s.pages[i];
          final isCurrent = i == s.index;
          final path = isCurrent && _comparing
              ? (s.comparePreview ?? s.previewFor(p))
              : s.previewFor(p);
          // Round 11, P0-8: no big spinner. Until the quick image is made
          // (a moment), the crop shows softened; the small ring says more
          // is coming.
          final waiting = path == null ? s.quickFor(p) : null;
          if (path == null && waiting == null) return const SizedBox.expand();
          final fingers = isCurrent && !_comparing && !p.edits.fingersRemoved
              ? s.currentFingers
              : null;
          final Widget image = waiting != null
              ? ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Image.file(
                    File(waiting),
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                )
              : Stack(
                  children: [
                    Image.file(
                      File(path!),
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    ),
                    if (fingers != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FingerOutlinePainter(
                            fingers.outline,
                            color: c.accent,
                          ),
                        ),
                      ),
                  ],
                );
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x6,
              Space.x8,
              Space.x6,
              64,
            ),
            child: Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 28,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: isCurrent && _comparing
                      ? image
                      // Sliders run on the GPU with the export's own a·x + b
                      // mapping: no re-render per move.
                      : ColorFiltered(
                          colorFilter: sliderColorFilter(
                            isCurrent ? live : p.edits,
                          ),
                          child: image,
                        ),
                ),
              ),
            ),
          );
        }

        // Round 10, P0-1: Back goes to Adjust edges (same pages, same page
        // open), never "Discard?". Only leaving the scan flow asks.
        return PopScope(
          canPop: !saving,
          child: AppScaffold(
            topBar: AppTopBar(
              title: l.enhanceTitle,
              subtitle: multi && page != null
                  ? l.pageOfTotal(s.index + 1, s.pages.length)
                  : null,
              actions: [
                TopBarTextAction(
                  label: l.enhanceDone,
                  onPressed: page == null || saving ? null : () => _save(bloc),
                ),
              ],
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    // ---- preview ----
                    Expanded(
                      child: ColoredBox(
                        color: _stage,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ZoomablePages(
                                controller: _pages,
                                zoom: _zoom,
                                itemCount: s.pages.length,
                                onPageChanged: (i) =>
                                    bloc.add(EditorPageSelected(i)),
                                itemBuilder: pageImage,
                              ),
                            ),
                            if (_adjustOpen)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () =>
                                      setState(() => _adjustOpen = false),
                                ),
                              ),
                            if (multi)
                              Positioned(
                                top: 10,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: _PageDots(
                                    count: s.pages.length,
                                    index: s.index,
                                  ),
                                ),
                              ),
                            // Round 11b (EnhanceV11): only the small ring
                            // over the page; Compare and the fingers chip
                            // sit under it.
                            if (s.rendering && !_comparing)
                              Positioned(
                                top: Space.x2,
                                right: Space.x3,
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: c.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // ---- under the page: Hold to compare · fingers ----
                    ColoredBox(
                      color: _stage,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
                        child: Row(
                          children: [
                            _CompareButton(
                              comparing: _comparing,
                              onChanged: (v) => setState(() => _comparing = v),
                            ),
                            const Spacer(),
                            if (page != null && !_comparing)
                              _FingersChip(
                                found: s.currentFingers != null && !page.edits.fingersRemoved,
                                undo: s.fingersUndoPage == page.id && page.edits.fingersRemoved,
                                onRemove: () => bloc.add(const EditorFingersRemoved(remove: true)),
                                onUndo: () => bloc.add(const EditorFingersRemoved(remove: false)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // ---- Adjust panel (above the bar) ----
                    AnimatedSize(
                      duration: Motion.normal,
                      curve: Curves.easeOutCubic,
                      child: !_adjustOpen
                          ? const SizedBox(width: double.infinity)
                          : ColoredBox(
                              color: _bar,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Space.x4,
                                  Space.x3,
                                  Space.x4,
                                  0,
                                ),
                                child: Column(
                                  children: [
                                    LabeledSlider(
                                      label: l.enhanceBrightness,
                                      value: _brightness ?? edits.brightness,
                                      onChanged: (v) {
                                        setState(() => _brightness = v);
                                        bloc.add(EditorBrightnessChanged(v));
                                      },
                                      onChangeEnd: (_) =>
                                          setState(() => _brightness = null),
                                    ),
                                    LabeledSlider(
                                      label: l.enhanceContrast,
                                      value: _contrast ?? edits.contrast,
                                      onChanged: (v) {
                                        setState(() => _contrast = v);
                                        bloc.add(EditorContrastChanged(v));
                                      },
                                      onChangeEnd: (_) =>
                                          setState(() => _contrast = null),
                                    ),
                                    // Round 11b: Reset lives with the sliders.
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: s.canReset && !saving
                                            ? () {
                                                setState(() {
                                                  _brightness = null;
                                                  _contrast = null;
                                                });
                                                bloc.add(const EditorLookReset());
                                              }
                                            : null,
                                        icon: const AppIcon(AppIcons.reset, size: 16),
                                        label: Text(l.enhanceReset),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    // ---- bottom bar ----
                    ColoredBox(
                      color: _bar,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: _FilterSwatch.heightFor(context),
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: FilterType.values.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: Space.x2),
                                  itemBuilder: (context, i) {
                                    final f = FilterType.values[i];
                                    return _FilterSwatch(
                                      filter: f,
                                      label: filterLabel(context, f),
                                      selected: edits.filter == f,
                                      thumb: page == null
                                          ? null
                                          : s.filterThumbs[page.id]?[f],
                                      onTap: () =>
                                          bloc.add(EditorFilterChanged(f)),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                // Round 11b: Crop · Adjust · Apply to all.
                                child: Row(
                                  children: [
                                    // Back to Adjust edges on this page (round
                                    // 10, P0-1); Next returns here.
                                    Expanded(
                                      child: _BarButton(
                                        icon: AppIcons.autoEdges,
                                        label: l.enhanceCrop,
                                        onTap: saving ? null : () => context.pop(),
                                      ),
                                    ),
                                    const SizedBox(width: Space.x2),
                                    Expanded(
                                      child: _BarButton(
                                        icon: AppIcons.edit,
                                        label: l.enhanceAdjust,
                                        active: _adjustOpen,
                                        onTap: () => setState(() => _adjustOpen = !_adjustOpen),
                                      ),
                                    ),
                                    if (multi) ...[
                                      const SizedBox(width: Space.x2),
                                      Expanded(
                                        child: _BarButton(
                                          icon: AppIcons.pages,
                                          label: l.enhanceApplyAll,
                                          filled: s.applyAll,
                                          onTap: () => bloc.add(EditorApplyAllToggled(!s.applyAll)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (saving) ProgressOverlay(label: l.sharePreparing),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Page dots: the current page is a wide amber pill.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: Motion.fast,
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? c.accent : const Color(0xFF4A4E56),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// Outlined pill button in the bottom bar (Adjust, Reset).
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.filled = false,
  });
  final AppIcons icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  /// An on / off chip that is on: filled amber (Apply to all).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final fg = !enabled
        ? c.muted.withValues(alpha: 0.5)
        : filled
        ? c.onAccent
        : (active ? c.accentText : c.text);
    return Semantics(
      toggled: filled,
      child: Material(
      color: filled ? c.accent : (active ? c.accentSoft : Colors.transparent),
      shape: StadiumBorder(
        side: BorderSide(color: filled || active ? c.accent : _EnhanceViewState._outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: context.text.labelLarge?.copyWith(
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CompareButton extends StatelessWidget {
  const _CompareButton({required this.comparing, required this.onChanged});

  final bool comparing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    // Round 11, P1-12: "◐ Compare", hold to see the crop without filter
    // or finger removal; 48 dp touch target.
    return Semantics(
      button: true,
      label: l.enhanceHoldToCompare,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onChanged(true),
        onTapUp: (_) => onChanged(false),
        onTapCancel: () => onChanged(false),
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.fast,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: comparing ? 0.8 : 0.55),
                borderRadius: Radii.pillR,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.compare, size: 16, color: c.text),
                  const SizedBox(width: 6),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(
                      comparing ? l.filterOriginal : l.enhanceHoldToCompare,
                      maxLines: 1,
                      style: context.text.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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

/// Round 11, P1-11: "Fingers found · Remove", then "Fingers removed ·
/// Undo" for 4 s.
class _FingersChip extends StatelessWidget {
  const _FingersChip({
    required this.found,
    required this.undo,
    required this.onRemove,
    required this.onUndo,
  });

  final bool found;
  final bool undo;
  final VoidCallback onRemove;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return AnimatedSwitcher(
      duration: Motion.fast,
      child: !found && !undo
          ? const SizedBox.shrink()
          : ConstrainedBox(
              key: ValueKey(undo),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 160,
              ),
              child: Material(
                color: Colors.black.withValues(alpha: 0.78),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: undo ? onUndo : onRemove,
                  child: SizedBox(
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.3,
                          child: Text.rich(
                            TextSpan(
                              style: context.text.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(
                                  text: undo ? l.fingersRemoved : l.fingersFound,
                                ),
                                const TextSpan(text: ' · '),
                                TextSpan(
                                  text: undo ? l.commonUndo : l.fingersRemove,
                                  style: TextStyle(
                                    color: c.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The fingers' outline over the page: thin amber (1.5 dp), the same line
/// as the camera's page outline. [outline] is normalised to the page.
class FingerOutlinePainter extends CustomPainter {
  FingerOutlinePainter(this.outline, {required this.color});

  final List<List<Pt>> outline;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    for (final c in outline) {
      if (c.length < 2) continue;
      final path = Path()
        ..moveTo(c.first.x * size.width, c.first.y * size.height);
      for (final pt in c.skip(1)) {
        path.lineTo(pt.x * size.width, pt.y * size.height);
      }
      canvas.drawPath(path..close(), paint);
    }
  }

  @override
  bool shouldRepaint(FingerOutlinePainter old) =>
      old.outline != outline || old.color != color;
}

/// A filter preset drawn as a tiny page in that filter's paper and ink.
class _FilterSwatch extends StatelessWidget {
  const _FilterSwatch({
    required this.filter,
    required this.label,
    required this.selected,
    required this.onTap,
    this.thumb,
  });

  final FilterType filter;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Real 160 px render of this filter on the page; the drawn swatch shows
  /// until it is ready.
  final String? thumb;

  static const _labelSize = 10.5;
  static const _labelHeight = 1.15;
  static const _maxLabelScale = 1.3;

  /// Thumbnail, gap and two label lines at the (capped) system font size.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _maxLabelScale);
    return 64 +
        5 +
        (scaler.scale(_labelSize) * _labelHeight * 2).ceilToDouble() +
        2;
  }

  static (Color paper, Color ink) _tone(FilterType f) => switch (f) {
    FilterType.original => (const Color(0xFFE9E3D8), const Color(0xFF8E9196)),
    FilterType.auto => (const Color(0xFFFFFFFF), const Color(0xFF4A4D55)),
    FilterType.idColor => (const Color(0xFFE3EEE6), const Color(0xFF2E5B45)),
    FilterType.colorBoost => (const Color(0xFFFFFDF6), const Color(0xFF24406E)),
    FilterType.grayscale => (const Color(0xFFF2F2F2), const Color(0xFF6B6B6B)),
    FilterType.bwPrint => (const Color(0xFFFFFFFF), const Color(0xFF000000)),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (paper, ink) = _tone(filter);
    Widget line(double w, double h) => Container(
      margin: const EdgeInsets.only(bottom: 5),
      width: w,
      height: h,
      color: ink,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          child: Column(
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: 52,
                height: 64,
                padding: const EdgeInsets.all(Space.x1),
                decoration: BoxDecoration(
                  borderRadius: Radii.smR,
                  border: Border.all(
                    color: selected ? c.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: thumb != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.file(
                          File(thumb!),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          gaplessPlayback: true,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: paper,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: Space.x2,
                        ),
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            line(22, 4),
                            line(36, 2),
                            line(36, 2),
                            line(27, 2),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              // Capped like a nav bar label: the strip has a fixed height.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: _maxLabelScale,
                child: FitText(
                  label,
                  style: context.text.labelSmall?.copyWith(
                    fontSize: _labelSize,
                    height: _labelHeight,
                    fontWeight: FontWeight.w700,
                    color: selected ? c.accentText : c.muted,
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

/// The brightness / contrast sliders as a colour matrix. Offsets in a
/// Flutter colour matrix are in 0..255, matching `a·x + b` in the pipeline;
/// results are clamped just like `convertTo` on export.
ColorFilter sliderColorFilter(PageEdits edits) {
  if (!edits.hasSliders) {
    return const ColorFilter.matrix([
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
  final t = edits.sliderTransform;
  final a = t.alpha;
  final b = t.beta;
  return ColorFilter.matrix([
    a,
    0,
    0,
    0,
    b,
    0,
    a,
    0,
    0,
    b,
    0,
    0,
    a,
    0,
    b,
    0,
    0,
    0,
    1,
    0,
  ]);
}
