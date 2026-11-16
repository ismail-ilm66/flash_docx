import 'dart:async';
import 'dart:io';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/utils/step_timer.dart';
import 'package:flash_dox/features/documents/data/services/smart_namer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/domain/snap_guide.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'page_editor_event.dart';
part 'page_editor_state.dart';

/// Drives Adjust edges and Enhance. Keeps every page's edits in memory,
/// renders previews off-thread, and persists on [EditorSaveRequested].
@injectable
class PageEditorBloc extends Bloc<PageEditorEvent, PageEditorState> {
  PageEditorBloc(
    this._processor,
    this._files,
    this._createDocument,
    this._addPages,
    this._updatePages,
    this._logActivity,
    this._renderService,
    this._prepare,
    this._previews,
    this._namer,
    this._bases,
    @factoryParam EditorArgs args,
  ) : super(
        PageEditorState(
          args: args,
          pages: args.pages,
          index: args.initialIndex,
        ),
      ) {
    on<EditorStarted>(_onStarted);
    on<EditorPageSelected>(_onPageSelected);
    on<EditorCornerMoved>(_onCornerMoved);
    on<EditorCornerDragEnded>((_, _) {});
    on<EditorBlurryKept>((_, emit) {
      final id = state.current?.id;
      if (id != null) emit(state.copyWith(blurryPages: {...state.blurryPages}..remove(id)));
    });
    on<EditorEnhanceClosed>((_, _) {
      // Back on Adjust edges: the crop may change, so stop preparing looks.
      _onEnhance = false;
      _prefetchCancel?.cancel();
    });
    on<EditorRotated>(_onRotated);
    on<EditorAutoEdgesRequested>(_onAutoEdges);
    on<EditorFilterChanged>(_onFilter);
    on<EditorBrightnessChanged>(_onBrightness);
    on<EditorContrastChanged>(_onContrast);
    on<EditorLookReset>(_onLookReset);
    on<EditorPagesAdded>(_onPagesAdded);
    on<EditorPageDeleted>(_onPageDeleted);
    on<EditorPageRetaken>(_onRetaken);
    // Preview renders are debounced and restartable: a newer request cancels
    // the pending one, and the isolate queue keeps them serial.
    on<EditorPreviewRequested>(
      _onPreview,
      transformer: _debounceRestartable(
        const Duration(milliseconds: Limits.sliderDebounceMs),
      ),
    );
    on<EditorSaveRequested>(_onSave);
    on<EditorCropChanged>(_onCropChanged);
    on<EditorApplyAllToggled>((e, emit) {
      emit(state.copyWith(applyAll: e.on));
      if (e.on) _spreadLook(emit);
    });
    on<EditorFilterThumbsRequested>(_onFilterThumbs);
    on<EditorSnapsRequested>(_onSnapsRequested);
    on<EditorStripThumbsRequested>(_onStripThumbs, transformer: droppable());
  }

  final ImageProcessor _processor;
  final FileStore _files;
  final CreateDocument _createDocument;
  final AddPages _addPages;
  final UpdatePages _updatePages;
  final LogActivity _logActivity;
  final PageRenderService _renderService;
  final PreparePages _prepare;
  final PreviewCache _previews;
  final SmartNamer _namer;
  final CleanBaseService _bases;

  /// Set once the scan was saved or the user confirmed discarding it, so the
  /// editor screens pop without asking again.
  bool popAllowed = false;

  bool get holdsUnsavedScan =>
      state.args.isNewDocument || state.args.addingPages;
  bool get guardBack => holdsUnsavedScan && !popAllowed;

  static EventTransformer<E> _debounceRestartable<E>(Duration d) {
    return (events, mapper) => restartable<E>()(
      events.transform(_DebounceTransformer<E>(d)),
      mapper,
    );
  }

  // ---------- lifecycle ----------

  Future<void> _onStarted(
    EditorStarted e,
    Emitter<PageEditorState> emit,
  ) async {
    emit(state.copyWith(status: EditorStatus.loading, clearFailure: true));
    try {
      // Base previews: upright original, downscaled, no crop/filter. New
      // scans already have them from ingest; saved documents render them
      // here, current page first so the screen is usable straight away.
      final order = [
        if (state.current != null) state.current!,
        ...state.pages.where((p) => p.id != state.current?.id),
      ];
      var shown = false;
      for (final page in order) {
        if (isClosed) return;
        if (state.basePreviews.containsKey(page.id)) continue;
        final path = _files.basePreviewPath(page.id, page.originalPath);
        if (!File(path).existsSync()) {
          await _processor.render(
            page.originalPath,
            const PageEdits(filter: FilterType.original),
            size: RenderSize.preview,
            outputPath: path,
            jpegQuality: 85,
            priority: JobPriority.interactive,
          );
        }
        if (isClosed) return;
        emit(
          state.copyWith(
            basePreviews: {...state.basePreviews, page.id: path},
            status: shown ? null : EditorStatus.idle,
          ),
        );
        if (!shown) {
          shown = true;
          add(const EditorPreviewRequested());
        }
      }
      if (!shown) {
        emit(state.copyWith(status: EditorStatus.idle));
        add(const EditorPreviewRequested());
      }
      add(const EditorStripThumbsRequested());
    } catch (err) {
      emit(
        state.copyWith(
          status: EditorStatus.failed,
          failure: ImageProcessingFailure(err.toString()),
        ),
      );
    }
  }

  /// Every page's crop-only preview, so the Adjust strip never shows an
  /// uncropped photo (P0-3). The current page gets its own with each edit
  /// through [EditorPreviewRequested].
  Future<void> _onStripThumbs(EditorStripThumbsRequested e, Emitter<PageEditorState> emit) async {
    for (final page in [...state.pages]) {
      if (isClosed) return;
      final want = _files.quickPath(page.id, page.originalPath, page.edits);
      if (state.quickPreviews[page.id] == want) continue;
      try {
        final q = await _previews.quick(page);
        if (isClosed) return;
        emit(_withQuick(page, q));
      } on Object catch (err) {
        debugPrint('[editor] strip thumb: $err');
      }
    }
  }

  void _onPageSelected(EditorPageSelected e, Emitter<PageEditorState> emit) {
    if (e.index < 0 || e.index >= state.pages.length) return;
    emit(state.copyWith(index: e.index));
    add(const EditorPreviewRequested());
  }

  // ---------- edits ----------

  void _updateCurrent(
    Emitter<PageEditorState> emit,
    PageEdits Function(PageEdits) f, {
    bool preview = true,
  }) {
    final cur = state.current;
    if (cur == null) return;
    final pages = [...state.pages];
    pages[state.index] = cur.withEdits(f(cur.edits));
    emit(state.copyWith(pages: pages));
    if (preview) add(const EditorPreviewRequested());
  }

  // No render while the corners move or rest: a look takes ~5 s on a
  // Kirin 710 and can't be stopped once started, so renders for in-between
  // crops piled up (measured 15 Nov 2026). Enhance renders on Next.
  void _onCornerMoved(EditorCornerMoved e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) {
        final q = (ed.crop ?? Quad.full()).withPoint(
          e.corner,
          e.point.clamp01(),
        );
        // A bent or self-crossing shape is rejected: the corner stays put.
        if (!q.isConvex || q.area < 0.01) return ed;
        return ed.copyWith(crop: q);
      },
      preview: false,
    );
  }

  void _onCropChanged(EditorCropChanged e, Emitter<PageEditorState> emit) {
    final q = e.quad.clamp01();
    // A bent, crossed or mirrored shape is rejected: the crop stays put.
    if (!q.isConvex || q.area < 0.01) return;
    _updateCurrent(emit, (ed) => ed.copyWith(crop: q), preview: false);
  }

  final Set<String> _snapsInFlight = {};

  Future<void> _onSnapsRequested(
    EditorSnapsRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    final cur = state.current;
    final base = state.basePreview;
    if (cur == null ||
        base == null ||
        state.snaps.containsKey(cur.id) ||
        !_snapsInFlight.add(cur.id)) {
      return;
    }
    try {
      final c = await _processor.snapCandidates(
        base,
        aspectHint: ScanModeRules.of(state.args.mode).aspectRatio,
      );
      if (!isClosed) emit(state.copyWith(snaps: {...state.snaps, cur.id: c}));
    } catch (err) {
      debugPrint('snap candidates failed: $err');
    } finally {
      _snapsInFlight.remove(cur.id);
    }
  }

  final Set<String> _thumbsInFlight = {};

  Future<void> _onFilterThumbs(
    EditorFilterThumbsRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    final cur = state.current;
    if (cur == null) return;
    final outputs = {
      for (final f in FilterType.values)
        f: _files.stripPath(cur.id, cur.originalPath, cur.edits, f),
    };
    final key = outputs[FilterType.original]!;
    if (state.filterThumbs[cur.id]?[FilterType.original] == key ||
        !_thumbsInFlight.add(key)) {
      return;
    }
    try {
      // The big image first: the strip queues behind the look being made.
      final look = _lookDone;
      if (look != null && !look.isCompleted) await look.future;
      if (!outputs.values.every((p) => File(p).existsSync())) {
        await _processor.renderFilterStrip(
          cur.originalPath,
          cur.edits,
          outputs: outputs,
        );
      }
      if (!isClosed) {
        emit(
          state.copyWith(
            filterThumbs: {...state.filterThumbs, cur.id: outputs},
          ),
        );
      }
    } catch (err) {
      debugPrint('filter strip failed: $err');
    } finally {
      _thumbsInFlight.remove(key);
    }
  }

  void _onRotated(EditorRotated e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) => e.clockwise ? ed.rotateRight() : ed.rotateLeft(),
    );
  }

  Future<void> _onAutoEdges(
    EditorAutoEdgesRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    final cur = state.current;
    if (cur == null) return;
    final rules = ScanModeRules.of(state.args.mode);
    // Detect on the ~1600 px base preview rather than the 12 MP original;
    // corners are normalised, so they apply to the original unchanged.
    final quad = await _processor.detectEdges(
      state.basePreview ?? cur.originalPath,
      snapAspectRatio: rules.aspectRatio,
    );
    final pages = [...state.pages];
    pages[state.index] = cur.copyWith(edgesDetected: quad != null);
    emit(state.copyWith(pages: pages));
    _updateCurrent(
      emit,
      (ed) => ed.copyWith(crop: quad ?? Quad.full(inset: 0.05)),
    );
  }

  void _onFilter(EditorFilterChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(emit, (ed) => ed.copyWith(filter: e.filter));
    _spreadLook(emit);
  }

  /// With "All N pages" on, the current page's look goes to every page.
  void _spreadLook(Emitter<PageEditorState> emit) {
    final cur = state.current;
    if (!state.applyAll || cur == null || state.pages.length < 2) return;
    final pages = [
      for (final pg in state.pages)
        pg.id == cur.id ||
                (pg.edits.filter == cur.edits.filter &&
                    pg.edits.brightness == cur.edits.brightness &&
                    pg.edits.contrast == cur.edits.contrast)
            ? pg
            : pg.withEdits(pg.edits.applyLook(cur.edits)),
    ];
    emit(state.copyWith(pages: pages));
  }

  void _onBrightness(EditorBrightnessChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) => ed.copyWith(brightness: e.value),
      preview: false,
    );
    _spreadLook(emit);
  }

  void _onContrast(EditorContrastChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) => ed.copyWith(contrast: e.value),
      preview: false,
    );
    _spreadLook(emit);
  }

  /// Reset (P1-1): filter and sliders back to the mode default; the crop is
  /// left alone. With "All N pages" on, every page.
  void _onLookReset(EditorLookReset e, Emitter<PageEditorState> emit) {
    PageEdits reset(PageEdits ed) =>
        ed.copyWith(filter: state.defaultFilter, brightness: 0, contrast: 0);
    if (state.applyAll) {
      final pages = [
        for (final pg in state.pages)
          pg.edits == reset(pg.edits) ? pg : pg.withEdits(reset(pg.edits)),
      ];
      emit(state.copyWith(pages: pages));
      add(const EditorPreviewRequested());
    } else {
      _updateCurrent(emit, reset);
    }
  }

  void _onPagesAdded(EditorPagesAdded e, Emitter<PageEditorState> emit) {
    if (e.pages.isEmpty) return;
    final start = state.pages.length;
    final pages = [
      ...state.pages,
      for (final (i, pg) in e.pages.indexed) pg.copyWith(order: start + i),
    ];
    emit(state.copyWith(pages: pages, index: start));
    // Builds base previews for the new pages, then the current preview and
    // the strip thumbnails.
    add(EditorStarted(state.args));
  }

  void _onPageDeleted(EditorPageDeleted e, Emitter<PageEditorState> emit) {
    if (state.pages.isEmpty) return;
    // Its cleaned base isn't needed any more if it hasn't started.
    _bases.cancel(state.pages[state.index].id);
    final pages = [...state.pages]..removeAt(state.index);
    emit(
      state.copyWith(
        pages: pages,
        index: state.index.clamp(0, pages.isEmpty ? 0 : pages.length - 1),
      ),
    );
    if (pages.isNotEmpty) add(const EditorPreviewRequested());
  }

  Future<void> _onRetaken(
    EditorPageRetaken e,
    Emitter<PageEditorState> emit,
  ) async {
    final cur = state.current;
    if (cur == null) return;
    emit(state.copyWith(status: EditorStatus.loading));
    try {
      // P0-3: the same pipeline as every new photo (orientation, detection
      // in the guide area, card auto-orientation), for this page's id and
      // side. The page keeps its place, side and chosen look.
      final r = await _prepare(
        [e.newOriginalPath],
        mode: state.args.mode,
        sides: [cur.side],
        fallbacks: [e.guide],
        captures: [e.capture],
        ids: [cur.id],
        copySource: false,
      );
      final fresh = r.fold(
        (f) => throw StateError('$f'),
        (pages) => pages.single,
      );
      final replaced = cur
          .copyWith(
            originalPath: fresh.originalPath,
            edgesDetected: fresh.edgesDetected,
          )
          .withEdits(
            fresh.edits.copyWith(
              filter: cur.edits.filter,
              brightness: cur.edits.brightness,
              contrast: cur.edits.contrast,
            ),
          );
      final pages = [...state.pages];
      pages[state.index] = replaced;
      final base = Map<String, String>.from(state.basePreviews)..remove(cur.id);
      emit(
        state.copyWith(
          pages: pages,
          basePreviews: base,
          status: EditorStatus.idle,
          // A new shot: the blur notice was about the old one.
          blurryPages: {...state.blurryPages}..remove(cur.id),
        ),
      );
      add(EditorStarted(state.args));
    } catch (err) {
      emit(
        state.copyWith(
          status: EditorStatus.failed,
          failure: ImageProcessingFailure(err.toString()),
        ),
      );
    }
  }

  // ---------- preview ----------

  CancelToken? _lookCancel;
  CancelToken? _prefetchCancel;

  /// Completes when the current page's look render ends (or fails).
  Completer<void>? _lookDone;

  /// Enhance is on screen (set by its first preview request, cleared when
  /// it closes). On Adjust edges nothing heavy runs (round 6, P0-2): the
  /// crop may still change, and a started render can't be stopped.
  bool _onEnhance = false;

  /// ID / passport pages are cleaned at the ID colour strength.
  bool get _card => state.args.mode != ScanMode.document && state.args.mode != ScanMode.photo;

  Future<void> _onPreview(
    EditorPreviewRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    _prefetchCancel?.cancel();
    if (e.forEnhance) _onEnhance = true;
    final cur = state.current;
    if (cur == null) return;
    if (!_onEnhance) {
      // Adjust edges: just this crop's placeholder for the strip.
      if (state.quickFor(cur) != null) return;
      try {
        final q = await _previews.quick(cur);
        if (!isClosed) emit(_withQuick(cur, q));
      } on Object catch (err) {
        debugPrint('[editor] quick preview: $err');
      }
      return;
    }
    final key = PageEditorState._previewKey(cur);
    if (!state.enhancePreviews.containsKey(key)) {
      final done = _lookDone = Completer<void>();
      try {
        if (!await _showCurrent(cur, key, emit)) return;
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }
    await _prefetchNeighbours(emit);
  }

  /// The filtered look of [cur] (round 6, P0-2):
  /// 1. already on disk (a filter shown before): at once;
  /// 2. the page's cleaned base is ready: the filter on its preview copy;
  /// 3. otherwise an instant image (quick bilateral clean-up + filter) right
  ///    away, then the cleaned base (queued first), then 2.
  /// False when superseded or failed.
  Future<bool> _showCurrent(
    ScanPage cur,
    String key,
    Emitter<PageEditorState> emit,
  ) async {
    final sw = StepTimer('enhance filter change → ${cur.edits.filter.name}');
    final onDisk = _files.lookPath(cur.id, cur.originalPath, cur.edits);
    if (File(onDisk).existsSync()) {
      _addLook(emit, cur, key, onDisk);
      sw
        ..lap('shown from disk')
        ..report();
      return true;
    }
    emit(state.copyWith(rendering: true));
    _lookCancel?.cancel();
    final token = _lookCancel = CancelToken();
    try {
      final String out;
      if (!CleanBaseService.covers(cur.edits)) {
        // The raw page (Original) or a passport photo: no cleaned base.
        out = await _renderLook(cur, cancel: token);
        sw.lap('look (queue + worker)');
      } else {
        final preview = _bases.previewPath(cur, card: _card);
        if (!File(preview).existsSync()) {
          final instant = _files.instantLookPath(cur.id, cur.originalPath, cur.edits);
          if (!File(instant).existsSync()) {
            await _processor.renderInstantLook(
              cur.originalPath,
              cur.edits,
              workPath: _files.workPath(cur.id, cur.originalPath, cur.edits),
              outputPath: instant,
              cancel: token,
            );
          }
          if (isClosed) return false;
          emit(state.copyWith(enhancePreviews: {...state.enhancePreviews, PageEditorState._instantKey(cur): instant}));
          sw.lap('instant image (queue + worker)');
          debugPrint('[perf] enhance first image in ${sw.elapsedMs} ms');
          await _bases.ensure(cur, card: _card, priority: JobPriority.interactive);
          if (isClosed) return false;
          sw.lap('cleaned base (queue + worker)');
        }
        out = await _renderLookFromClean(cur, cancel: token);
        sw.lap('look from cleaned base (queue + worker)');
      }
      if (isClosed) return false;
      _addLook(emit, cur, key, out);
      sw.report();
      debugPrint(
        '[perf] enhance filter ${cur.edits.filter.name} in ${sw.elapsedMs} ms',
      );
      return true;
    } on JobCancelled {
      // Superseded by a newer request; it will set `rendering` itself.
      return false;
    } catch (err) {
      if (!isClosed) {
        emit(
          state.copyWith(
            rendering: false,
            failure: ImageProcessingFailure(err.toString()),
          ),
        );
      }
      return false;
    }
  }

  /// The next and previous pages' looks, so a swipe lands on the filtered
  /// page (an "All N pages" change included), then every other page's
  /// cleaned base, so Done and Share find them ready. Background lane,
  /// after a short pause so quick filter taps don't wait behind them.
  Future<void> _prefetchNeighbours(Emitter<PageEditorState> emit) async {
    final token = _prefetchCancel = CancelToken();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final i0 = state.index;
    final order = [
      for (final i in [i0 + 1, i0 - 1]) if (i >= 0 && i < state.pages.length) i,
      for (var i = 0; i < state.pages.length; i++) if ((i - i0).abs() > 1) i,
    ];
    for (final i in order) {
      if (token.isCancelled || emit.isDone || isClosed) return;
      final p = state.pages[i];
      final neighbour = (i - i0).abs() == 1;
      try {
        if (!CleanBaseService.covers(p.edits)) {
          if (!neighbour) continue;
          final key = PageEditorState._previewKey(p);
          if (state.enhancePreviews.containsKey(key)) continue;
          final onDisk = _files.lookPath(p.id, p.originalPath, p.edits);
          final out = File(onDisk).existsSync()
              ? onDisk
              : await _renderLook(p, priority: JobPriority.background, cancel: token);
          if (isClosed) return;
          _addLook(emit, p, key, out, settled: false);
          continue;
        }
        await _bases.ensure(p, card: _card);
        if (!neighbour || token.isCancelled || isClosed) continue;
        final key = PageEditorState._previewKey(p);
        if (state.enhancePreviews.containsKey(key)) continue;
        final onDisk = _files.lookPath(p.id, p.originalPath, p.edits);
        final out = File(onDisk).existsSync()
            ? onDisk
            : await _renderLookFromClean(p, priority: JobPriority.background, cancel: token);
        if (isClosed) return;
        _addLook(emit, p, key, out, settled: false);
      } on JobCancelled {
        if (token.isCancelled) return;
      } catch (err) {
        debugPrint('[editor] prefetch: $err');
      }
    }
  }

  Future<String> _renderLookFromClean(
    ScanPage p, {
    JobPriority priority = JobPriority.interactive,
    CancelToken? cancel,
  }) => _processor.renderLookFromClean(
    _bases.previewPath(p, card: _card),
    p.edits,
    outputPath: _files.lookPath(p.id, p.originalPath, p.edits),
    autoPath: _files.autoBasePath(p.id, p.originalPath, p.edits),
    priority: priority,
    cancel: cancel,
  );

  Future<String> _renderLook(
    ScanPage p, {
    JobPriority priority = JobPriority.interactive,
    CancelToken? cancel,
  }) => _processor.renderLook(
    p.originalPath,
    p.edits,
    workPath: _files.workPath(p.id, p.originalPath, p.edits),
    outputPath: _files.lookPath(p.id, p.originalPath, p.edits),
    autoBasePath: _files.autoBasePath(p.id, p.originalPath, p.edits),
    priority: priority,
    cancel: cancel,
  );

  /// Every look is kept (at most one per filter and crop), so going back to
  /// a filter is instant. [settled]: the current page's render is done.
  void _addLook(
    Emitter<PageEditorState> emit,
    ScanPage p,
    String key,
    String path, {
    bool settled = true,
  }) {
    _previews.remember(p.id, path);
    emit(
      state.copyWith(
        enhancePreviews: {...state.enhancePreviews, key: path},
        rendering: settled ? false : null,
      ),
    );
  }

  PageEditorState _withQuick(ScanPage p, String path) => state.copyWith(
    quickPreviews: {...state.quickPreviews, p.id: path},
    quickShapes: {...state.quickShapes, p.id: PageEditorState.shapeOf(p)},
  );

  @override
  Future<void> close() {
    _prefetchCancel?.cancel();
    return super.close();
  }

  // ---------- save ----------

  Future<void> _onSave(
    EditorSaveRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    if (state.pages.isEmpty) return;
    emit(state.copyWith(status: EditorStatus.saving, clearFailure: true));
    final args = state.args;
    var pages = [
      for (final (i, pg) in state.pages.indexed) pg.copyWith(order: i),
    ];
    // Editing a saved document: a retaken page's new original is still in the
    // temp folder (wiped on next launch). Move it into the document first.
    if (!args.isNewDocument && !args.addingPages) {
      try {
        pages = [
          for (final pg in pages)
            _files.isInDoc(args.documentId!, pg.originalPath)
                ? pg
                : pg.copyWith(
                    documentId: args.documentId!,
                    originalPath: await _files.adoptOriginal(
                      sourcePath: pg.originalPath,
                      docId: args.documentId!,
                      pageId: pg.id,
                    ),
                  ),
        ];
      } catch (err) {
        emit(
          state.copyWith(
            status: EditorStatus.failed,
            failure: StorageFailure(err.toString()),
          ),
        );
        return;
      }
    }
    final result = args.isNewDocument
        ? await _createDocument(mode: args.mode, pages: pages)
        : args.addingPages
        ? (await _addPages(args.documentId!, pages)).map((_) => null)
        : (await _updatePages(pages)).map((_) => null);

    await result.fold(
      (f) async =>
          emit(state.copyWith(status: EditorStatus.failed, failure: f)),
      (doc) async {
        final docId = doc?.id ?? args.documentId!;
        if (!args.isNewDocument && !args.addingPages) {
          await _logActivity(docId, ActivityType.edited);
        }
        popAllowed = true;
        emit(
          state.copyWith(status: EditorStatus.saved, savedDocumentId: docId),
        );
        // Warm caches in the background; the viewer shows originals until then.
        unawaited(
          _renderService
              .ensureCachesFor(docId)
              .catchError(
                (Object e) => debugPrint('cache warm failed: $e'),
              ),
        );
        // A new scan gets a smart-name suggestion (feature 3).
        if (args.isNewDocument) unawaited(_namer.suggestFor(docId));
      },
    );
  }
}

/// Simple debounce transformer for events.
class _DebounceTransformer<E> extends StreamTransformerBase<E, E> {
  _DebounceTransformer(this.duration);
  final Duration duration;

  @override
  Stream<E> bind(Stream<E> stream) {
    late StreamController<E> ctrl;
    Timer? timer;
    E? last;
    StreamSubscription<E>? sub;
    ctrl = StreamController<E>(
      onListen: () {
        sub = stream.listen(
          (e) {
            last = e;
            timer?.cancel();
            timer = Timer(duration, () {
              if (last != null) ctrl.add(last as E);
            });
          },
          onError: ctrl.addError,
          onDone: () {
            timer?.cancel();
            ctrl.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        return sub?.cancel();
      },
    );
    return ctrl.stream;
  }
}
