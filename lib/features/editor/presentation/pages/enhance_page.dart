import 'dart:io';

import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Filters + brightness/contrast. Shares the [PageEditorBloc] created by
/// Adjust edges, so edits on both screens are one in-memory session.
class EnhancePage extends StatelessWidget {
  const EnhancePage({required this.bloc, super.key});

  final PageEditorBloc bloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: bloc..add(const EditorPreviewRequested(forEnhance: true)),
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

  /// "Apply to all pages" switch. While on, every look change is copied to
  /// the other pages (an in-memory edit, cheap).
  bool _applyAll = false;

  // Local slider values so the thumb follows the finger at 60 fps while the
  // bloc debounces the actual render.
  double? _brightness;
  double? _contrast;

  void _onSaved(BuildContext context, PageEditorState s) {
    final id = s.savedDocumentId!;
    final args = s.args;
    if (args.isNewDocument) {
      context.go(Routes.home);
      context.push(Routes.viewer(id));
    } else {
      // Pop Enhance and Adjust edges back to the viewer.
      context
        ..pop()
        ..pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PageEditorBloc, PageEditorState>(
      listenWhen: (a, b) =>
          a.status != b.status || a.index != b.index,
      listener: (context, s) {
        if (s.status == EditorStatus.saved) _onSaved(context, s);
        if (s.status == EditorStatus.failed && s.failure != null) {
          context.showSnack(failureMessage(context, s.failure), error: true);
        }
        setState(() { _brightness = null; _contrast = null; });
      },
      builder: (context, s) {
        final bloc = context.read<PageEditorBloc>();
        final page = s.current;
        final edits = s.edits;
        final preview = _comparing ? s.basePreview : (s.enhancePreview ?? s.basePreview);
        final multi = s.pages.length > 1;
        final saving = s.status == EditorStatus.saving;

        void changed() {
          if (_applyAll && multi) bloc.add(const EditorApplyLookToAll());
        }

        return AppScaffold(
          forceDark: true,
          topBar: AppTopBar(
            title: l.enhanceTitle,
            subtitle: multi && page != null ? l.pageOfTotal(s.index + 1, s.pages.length) : null,
            actions: [
              TopBarTextAction(
                label: l.enhanceDone,
                loading: saving,
                onPressed: page == null
                    ? null
                    : () {
                        changed();
                        bloc.add(const EditorSaveRequested());
                      },
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(Space.x10, Space.x2, Space.x10, 64),
                            child: Center(
                              child: preview == null
                                  ? const CircularProgressIndicator()
                                  : GestureDetector(
                                      onLongPressStart: (_) => setState(() => _comparing = true),
                                      onLongPressEnd: (_) => setState(() => _comparing = false),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 8))],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: _comparing
                                              ? RotatedBox(
                                                  quarterTurns: edits.normalizedTurns,
                                                  child: Image.file(File(preview), gaplessPlayback: true),
                                                )
                                              : Image.file(File(preview), key: ValueKey(preview), gaplessPlayback: true),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (s.rendering && !_comparing)
                          Positioned(
                            top: Space.x2,
                            right: Space.x5,
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                            ),
                          ),
                        if (multi)
                          Positioned(
                            left: Space.x3,
                            bottom: Space.x2,
                            child: PageDots(
                              count: s.pages.length,
                              index: s.index,
                              onSelect: (i) => bloc.add(EditorPageSelected(i)),
                            ),
                          ),
                        Positioned(
                          right: Space.x5,
                          bottom: Space.x4,
                          child: _CompareButton(
                            comparing: _comparing,
                            onChanged: (v) => setState(() => _comparing = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
                    ),
                    padding: const EdgeInsets.only(top: Space.x4, bottom: 18),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 98,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                              itemCount: FilterType.values.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final f = FilterType.values[i];
                                return _FilterSwatch(
                                  filter: f,
                                  label: filterLabel(context, f),
                                  selected: edits.filter == f,
                                  onTap: () {
                                    bloc.add(EditorFilterChanged(f));
                                    changed();
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: Space.x4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x5),
                            child: Column(
                              children: [
                                LabeledSlider(
                                  label: l.enhanceBrightness,
                                  value: _brightness ?? edits.brightness,
                                  onChanged: (v) {
                                    setState(() => _brightness = v);
                                    bloc.add(EditorBrightnessChanged(v));
                                  },
                                  onChangeEnd: (_) {
                                    setState(() => _brightness = null);
                                    changed();
                                  },
                                ),
                                const SizedBox(height: Space.x2),
                                LabeledSlider(
                                  label: l.enhanceContrast,
                                  value: _contrast ?? edits.contrast,
                                  onChanged: (v) {
                                    setState(() => _contrast = v);
                                    bloc.add(EditorContrastChanged(v));
                                  },
                                  onChangeEnd: (_) {
                                    setState(() => _contrast = null);
                                    changed();
                                  },
                                ),
                              ],
                            ),
                          ),
                          if (multi) ...[
                            const SizedBox(height: Space.x3),
                            MergeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.only(left: Space.x5, right: Space.x4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(l.enhanceApplyAll, style: context.text.labelLarge),
                                          const SizedBox(height: 2),
                                          Text(
                                            l.enhanceApplyAllHint(s.pages.length),
                                            style: context.text.bodySmall?.copyWith(color: c.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _applyAll,
                                      onChanged: saving
                                          ? null
                                          : (v) {
                                              setState(() => _applyAll = v);
                                              if (v) bloc.add(const EditorApplyLookToAll());
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (saving) ProgressOverlay(label: l.sharePreparing),
            ],
          ),
        );
      },
    );
  }
}

/// "Hold to compare" pill: shows the original while pressed.
class _CompareButton extends StatelessWidget {
  const _CompareButton({required this.comparing, required this.onChanged});

  final bool comparing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Semantics(
      button: true,
      label: l.enhanceHoldToCompare,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => onChanged(true),
        onTapUp: (_) => onChanged(false),
        onTapCancel: () => onChanged(false),
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: comparing ? 0.24 : 0.12),
            borderRadius: Radii.pillR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.compare, size: 16, color: c.text),
              const SizedBox(width: 6),
              Text(
                comparing ? l.filterOriginal : l.enhanceHoldToCompare,
                style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A filter preset drawn as a tiny page in that filter's paper and ink.
class _FilterSwatch extends StatelessWidget {
  const _FilterSwatch({
    required this.filter,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final FilterType filter;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static (Color paper, Color ink) _tone(FilterType f) => switch (f) {
        FilterType.original => (const Color(0xFFE9E3D8), const Color(0xFF8E9196)),
        FilterType.auto => (const Color(0xFFFFFFFF), const Color(0xFF4A4D55)),
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
          width: 64,
          child: Column(
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: 60,
                height: 76,
                padding: const EdgeInsets.all(Space.x1),
                decoration: BoxDecoration(
                  borderRadius: Radii.smR,
                  border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2),
                ),
                child: Container(
                  decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: Space.x2),
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [line(22, 4), line(36, 2), line(36, 2), line(27, 2)],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? c.accentText : c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
