import 'dart:async';
import 'dart:io';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
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
    @factoryParam EditorArgs args,
  ) : super(PageEditorState(args: args, pages: args.pages, index: args.initialIndex)) {
    on<EditorStarted>(_onStarted);
    on<EditorPageSelected>(_onPageSelected);
    on<EditorCornerMoved>(_onCornerMoved);
    on<EditorCornerDragEnded>((_, __) {});
    on<EditorRotated>(_onRotated);
    on<EditorAutoEdgesRequested>(_onAutoEdges);
    on<EditorFilterChanged>(_onFilter);
    on<EditorBrightnessChanged>(_onBrightness);
    on<EditorContrastChanged>(_onContrast);
    on<EditorLookReset>(_onLookReset);
    on<EditorApplyLookToAll>(_onApplyToAll);
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
  }

  final ImageProcessor _processor;
  final FileStore _files;
  final CreateDocument _createDocument;
  final AddPages _addPages;
  final UpdatePages _updatePages;
  final LogActivity _logActivity;
  final PageRenderService _renderService;

  /// Set once the scan was saved or the user confirmed discarding it, so the
  /// editor screens pop without asking again.
  bool popAllowed = false;

  bool get holdsUnsavedScan => state.args.isNewDocument || state.args.addingPages;
  bool get guardBack => holdsUnsavedScan && !popAllowed;

  static EventTransformer<E> _debounceRestartable<E>(Duration d) {
    return (events, mapper) => restartable<E>()(
          events.transform(_DebounceTransformer<E>(d)),
          mapper,
        );
  }

  // ---------- lifecycle ----------

  Future<void> _onStarted(EditorStarted e, Emitter<PageEditorState> emit) async {
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
    } catch (err) {
      emit(
        state.copyWith(
          status: EditorStatus.failed,
          failure: ImageProcessingFailure(err.toString()),
        ),
      );
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

  void _onCornerMoved(EditorCornerMoved e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) {
        final q = (ed.crop ?? Quad.full()).withPoint(e.corner, e.point.clamp01());
        // A bent or self-crossing shape is rejected: the corner stays put.
        if (!q.isConvex || q.area < 0.01) return ed;
        return ed.copyWith(crop: q);
      },
      preview: false,
    );
  }

  void _onRotated(EditorRotated e, Emitter<PageEditorState> emit) {
    _updateCurrent(emit, (ed) => e.clockwise ? ed.rotateRight() : ed.rotateLeft());
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
    _updateCurrent(emit, (ed) => ed.copyWith(crop: quad ?? Quad.full(inset: 0.05)));
  }

  void _onFilter(EditorFilterChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(emit, (ed) => ed.copyWith(filter: e.filter));
  }

  void _onBrightness(EditorBrightnessChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(emit, (ed) => ed.copyWith(brightness: e.value), preview: false);
  }

  void _onContrast(EditorContrastChanged e, Emitter<PageEditorState> emit) {
    _updateCurrent(emit, (ed) => ed.copyWith(contrast: e.value), preview: false);
  }

  void _onLookReset(EditorLookReset e, Emitter<PageEditorState> emit) {
    _updateCurrent(
      emit,
      (ed) => ed.copyWith(filter: FilterType.auto, brightness: 0, contrast: 0),
    );
  }

  void _onApplyToAll(EditorApplyLookToAll e, Emitter<PageEditorState> emit) {
    final cur = state.current;
    if (cur == null) return;
    final pages = [
      for (final pg in state.pages)
        pg.id == cur.id ? pg : pg.withEdits(pg.edits.applyLook(cur.edits)),
    ];
    emit(state.copyWith(pages: pages, appliedToAllTick: state.appliedToAllTick + 1));
  }

  void _onPagesAdded(EditorPagesAdded e, Emitter<PageEditorState> emit) {
    if (e.pages.isEmpty) return;
    final start = state.pages.length;
    final pages = [
      ...state.pages,
      for (final (i, pg) in e.pages.indexed) pg.copyWith(order: start + i),
    ];
    emit(state.copyWith(pages: pages, index: start));
    // Builds base previews for the new pages, then the current preview.
    add(EditorStarted(state.args));
  }

  void _onPageDeleted(EditorPageDeleted e, Emitter<PageEditorState> emit) {
    if (state.pages.isEmpty) return;
    final pages = [...state.pages]..removeAt(state.index);
    emit(state.copyWith(pages: pages, index: state.index.clamp(0, pages.isEmpty ? 0 : pages.length - 1)));
    if (pages.isNotEmpty) add(const EditorPreviewRequested());
  }

  Future<void> _onRetaken(EditorPageRetaken e, Emitter<PageEditorState> emit) async {
    final cur = state.current;
    if (cur == null) return;
    emit(state.copyWith(status: EditorStatus.loading));
    try {
      final rules = ScanModeRules.of(state.args.mode);
      // Same single-decode ingest as every other new photo.
      final original = _files.newCapturePath('${cur.id}_${DateTime.now().microsecondsSinceEpoch}');
      final auto = await _processor.ingest(
        e.newOriginalPath,
        originalOut: original,
        previewOut: _files.basePreviewPath(cur.id, original),
        snapAspectRatio: rules.aspectRatio,
        filter: cur.edits.filter,
      );
      await File(e.newOriginalPath).delete().catchError((_) => File(e.newOriginalPath));
      final replaced = cur
          .copyWith(originalPath: original, edgesDetected: auto.detected)
          .withEdits(auto.edits);
      final pages = [...state.pages];
      pages[state.index] = replaced;
      final base = Map<String, String>.from(state.basePreviews)..remove(cur.id);
      emit(state.copyWith(pages: pages, basePreviews: base, status: EditorStatus.idle));
      add(EditorStarted(state.args));
    } catch (err) {
      emit(state.copyWith(status: EditorStatus.failed, failure: ImageProcessingFailure(err.toString())));
    }
  }

  // ---------- preview ----------

  Future<void> _onPreview(
    EditorPreviewRequested e,
    Emitter<PageEditorState> emit,
  ) async {
    final cur = state.current;
    if (cur == null) return;
    final key = PageEditorState._previewKey(cur);
    if (state.enhancePreviews.containsKey(key)) return;
    emit(state.copyWith(rendering: true));
    try {
      // Filter only, from the cached cropped page; sliders are live in the UI.
      final out = await _processor.renderLook(
        cur.originalPath,
        cur.edits,
        workPath: _files.workPath(cur.id, cur.originalPath, cur.edits),
        outputPath: _files.lookPath(cur.id, cur.originalPath, cur.edits),
      );
      if (isClosed) return;
      final map = Map<String, String>.from(state.enhancePreviews);
      // Keep the map small: drop older previews of this page.
      map.removeWhere((k, v) => k.startsWith('${cur.id}:') && k != key);
      map[key] = out;
      emit(state.copyWith(enhancePreviews: map, rendering: false));
    } catch (err) {
      if (!isClosed) {
        emit(state.copyWith(rendering: false, failure: ImageProcessingFailure(err.toString())));
      }
    }
  }

  // ---------- save ----------

  Future<void> _onSave(EditorSaveRequested e, Emitter<PageEditorState> emit) async {
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
                    originalPath: await _files.adoptOriginal(
                      sourcePath: pg.originalPath,
                      docId: args.documentId!,
                      pageId: pg.id,
                    ),
                  ),
        ];
      } catch (err) {
        emit(state.copyWith(status: EditorStatus.failed, failure: StorageFailure(err.toString())));
        return;
      }
    }
    final result = args.isNewDocument
        ? await _createDocument(mode: args.mode, pages: pages)
        : args.addingPages
            ? (await _addPages(args.documentId!, pages)).map((_) => null)
            : (await _updatePages(pages)).map((_) => null);

    await result.fold(
      (f) async => emit(state.copyWith(status: EditorStatus.failed, failure: f)),
      (doc) async {
        final docId = doc?.id ?? args.documentId!;
        if (!args.isNewDocument && !args.addingPages) {
          await _logActivity(docId, ActivityType.edited);
        }
        popAllowed = true;
        emit(state.copyWith(status: EditorStatus.saved, savedDocumentId: docId));
        // Warm caches in the background; the viewer shows originals until then.
        unawaited(
          _renderService.ensureCachesFor(docId).catchError(
            (Object e) => debugPrint('cache warm failed: $e'),
          ),
        );
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
