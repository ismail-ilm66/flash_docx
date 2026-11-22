import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/photo/domain/background_segmenter.dart';
import 'package:flash_dox/features/photo/domain/photo_frame.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/signature/presentation/pages/sign_document_page.dart'
    show dateStampText;
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// What the crop screen works on: a fresh photo, or a saved passport photo
/// being re-cropped.
class PhotoCropArgs {
  const PhotoCropArgs({required this.photoPath, this.page, this.addToDocumentId, this.size});

  final String photoPath;

  /// Set when re-cropping a saved photo.
  final ScanPage? page;

  /// Round 10, P1-8: "+ Add" another person's photo to this sheet. The
  /// photo takes the sheet's [size].
  final String? addToDocumentId;
  final PhotoSize? size;
}

/// What happens after the crop of a new photo (round 10, P1-8).
enum _After { preview, print }

/// Tools › Passport photo: take or pick one photo, then crop it. With
/// [addToDocumentId], another person's photo for that sheet, at [size].
Future<void> startPassportPhoto(BuildContext context, {String? addToDocumentId, PhotoSize? size}) async {
  final l = context.l10n;
  final camera = await AppBottomSheet.show<bool>(
    context,
    builder: (ctx) => AppBottomSheet(
      title: l.photoTitle,
      padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x4),
      child: Column(
        children: [
          SheetAction(
            label: l.photoTakePhoto,
            leading: const AppIcon(AppIcons.camera),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
          SheetAction(
            label: l.photoFromGallery,
            leading: const AppIcon(AppIcons.gallery),
            onTap: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    ),
  );
  if (camera == null || !context.mounted) return;
  final path = await _pickPhoto(context, camera: camera);
  if (path == null || !context.mounted) return;
  await context.push(
    Routes.photoCrop,
    extra: PhotoCropArgs(photoPath: path, addToDocumentId: addToDocumentId, size: size),
  );
}

Future<String?> _pickPhoto(BuildContext context, {required bool camera}) async {
  if (camera) {
    final shot = await context.push<RetakeShot>(
      Routes.camera,
      extra: const CameraArgs(
        retake: true,
        mode: ScanMode.document,
        hint: CameraHint.passportPhoto,
      ),
    );
    if (shot == null) return null;
    // The camera records how the phone was held; turn the photo upright.
    await getIt<ImageProcessor>().normalizeCapture(shot.path, shot.capture);
    return shot.path;
  }
  final r = await getIt<ImportService>().fromGallery(multiple: false);
  final path = r.fold((f) {
    if (context.mounted && f is! CancelledFailure) {
      context.showSnack(failureMessage(context, f), error: true);
    }
    return null;
  }, (paths) => paths.firstOrNull);
  // Imports: the EXIF tag only (P0-1), so every screen reads it the same.
  if (path != null) await getIt<ImageProcessor>().normalizeCapture(path, null);
  return path;
}

/// Passport photo, step 1 (feature 5, artboard *Passport photo · crop*): a
/// fixed frame at the photo size with face guides; the photo moves under
/// it. Background is Original only in v1.0 (owner question 3).
class PhotoCropPage extends StatefulWidget {
  const PhotoCropPage({required this.args, super.key});

  final PhotoCropArgs args;

  @override
  State<PhotoCropPage> createState() => _PhotoCropPageState();
}

class _PhotoCropPageState extends State<PhotoCropPage> {
  late String _photo = widget.args.photoPath;
  Size? _image;
  late PhotoSize _size = _initialSize();
  PhotoPlacement? _placement;
  Rect? _frame;
  bool _saving = false;
  bool _loadFailed = false;

  /// Background (artboard *Passport photo · crop*) and Enhance: the
  /// choices, the person mask for [_photo], whether segmentation works
  /// here (null while finding out) and a preview per combination.
  // Round 10, P1-7: a new photo starts on the colour chosen last, White at
  // first; a saved one keeps its own.
  late PhotoBackground _background =
      widget.args.page?.edits.photoBackground ??
      PhotoBackground.values.where((b) => b.name == getIt<PrefsService>().photoBackground).firstOrNull ??
      PhotoBackground.white;
  // New photos start Natural; a saved one keeps its choice (Off if it was
  // made before Enhance existed).
  late PhotoEnhance _enhance =
      widget.args.page?.edits.photoEnhance ?? PhotoEnhance.natural;
  late String? _mask = widget.args.page?.edits.backgroundMaskPath;
  bool? _segmentable;
  final Map<(PhotoBackground, PhotoEnhance), String> _previews = {};
  final Set<(PhotoBackground, PhotoEnhance)> _rendering = {};

  /// The last preview shown, kept on screen while the next one renders.
  String? _displayed;

  // Gesture state.
  PhotoPlacement? _start;
  Offset _startFocal = Offset.zero;

  PhotoSize _initialSize() {
    if (widget.args.size != null) return widget.args.size!;
    final e = widget.args.page?.edits;
    if (e?.photoWidthMm != null && e?.photoHeightMm != null) {
      return PhotoSize(e!.photoWidthMm!, e.photoHeightMm!);
    }
    return PhotoSize.passport;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSize());
  }

  Future<void> _loadSize() async {
    try {
      final s = await getIt<ImageProcessor>().imageSize(_photo);
      if (!mounted) return;
      setState(() {
        _image = Size(s.width.toDouble(), s.height.toDouble());
        _placement = null; // placed on the next layout
        _frame = null;
        _loadFailed = false;
      });
      if (_segmentable == null) unawaited(_segment());
    } on Object catch (e) {
      // Never an endless grey stage (P1-3.4): say so and offer Retake.
      debugPrint('[photo] size failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// The photo as it will print: with the chosen background and Enhance
  /// once that preview is ready (the previous one until then).
  String get _shown {
    final key = (_background, _enhance);
    if (key == (PhotoBackground.original, PhotoEnhance.off)) return _photo;
    return _previews[key] ?? _displayed ?? _photo;
  }

  /// Fits the frame into the stage, leaving room for the guide labels.
  Rect _frameFor(Size stage) {
    const pad = 36.0;
    final maxW = math.max(40.0, stage.width - pad * 2);
    final maxH = math.max(40.0, stage.height - pad * 2);
    var w = maxW;
    var h = w / _size.aspect;
    if (h > maxH) {
      h = maxH;
      w = h * _size.aspect;
    }
    return Rect.fromCenter(
      center: stage.center(Offset.zero),
      width: w,
      height: h,
    );
  }

  void _place(Rect frame) {
    final image = _image!;
    final saved = widget.args.page?.edits.crop;
    // The saved crop belongs to the saved photo, not to a retake.
    final keepOld =
        _placement == null &&
        saved != null &&
        _frame == null &&
        _photo == widget.args.photoPath;
    final p = keepOld
        ? PhotoPlacement.fromCrop(saved, image, frame)
        : _placement == null || _frame == null
        ? PhotoPlacement.cover(image, frame)
        // Frame changed (new size or layout): keep the same centre of interest.
        : PhotoPlacement.fromCrop(
            _placement!.cropFor(image, _frame!),
            image,
            frame,
          );
    _placement = p.clamp(image, frame);
    _frame = frame;
  }

  Future<void> _retake() async {
    final camera = widget.args.page == null;
    final path = await _pickPhoto(context, camera: camera);
    if (path == null || !mounted) return;
    setState(() {
      _photo = path;
      _image = null;
      _placement = null;
      _frame = null;
      _loadFailed = false;
      _mask = null;
      _segmentable = null;
      _previews.clear();
      _displayed = null;
    });
    await _loadSize();
  }

  /// Finds the person once per photo, then renders the previews. If
  /// segmentation isn't available the colour options go away; Enhance
  /// still works (without the wall's white balance).
  Future<void> _segment() async {
    final photo = _photo;
    final saved = _mask;
    final mask = saved != null && File(saved).existsSync()
        ? saved
        : await getIt<BackgroundSegmenter>().maskFor(photo);
    if (!mounted || photo != _photo) return;
    setState(() {
      _mask = mask;
      _segmentable = mask != null;
      if (mask == null) _background = PhotoBackground.original;
    });
    await _refreshPreviews();
  }

  /// The preview for the current choices first, then the two colours with
  /// the current Enhance, so tapping one is instant.
  Future<void> _refreshPreviews() async {
    if (_segmentable == null) return; // the mask (or its absence) first
    await _renderPreview((_background, _enhance));
    if (!(_segmentable ?? false)) return;
    for (final bg in PhotoBackgrounds.shown) {
      await _renderPreview((bg, _enhance));
    }
  }

  Future<void> _renderPreview((PhotoBackground, PhotoEnhance) key) async {
    if (key == (PhotoBackground.original, PhotoEnhance.off)) return;
    if (_previews.containsKey(key) || _rendering.contains(key)) return;
    final photo = _photo;
    final mask = _mask;
    if (key.$1 != PhotoBackground.original && mask == null) return;
    _rendering.add(key);
    try {
      final out = await getIt<ImageProcessor>().previewWithBackground(
        photo,
        mask,
        key.$1,
        enhance: key.$2,
        outputPath: getIt<FileStore>().newCapturePath(
          'bg_${key.$1.name}_${key.$2.name}_${newId()}',
        ),
      );
      if (!mounted || photo != _photo) return;
      setState(() {
        _previews[key] = out;
        if (key == (_background, _enhance)) _displayed = out;
      });
    } on Object catch (e) {
      debugPrint('[background] preview: $e');
    } finally {
      _rendering.remove(key);
    }
  }

  void _choose({PhotoBackground? background, PhotoEnhance? enhance}) {
    if (background != null) unawaited(getIt<PrefsService>().setPhotoBackground(background.name));
    setState(() {
      _background = background ?? _background;
      _enhance = enhance ?? _enhance;
      final ready = _previews[(_background, _enhance)];
      if (ready != null) _displayed = ready;
    });
    unawaited(_refreshPreviews());
  }

  /// Copies the mask into the document so it outlives the temp folder.
  Future<String> _adoptMask(
    String documentId,
    String pageId,
    String mask,
  ) async {
    final out = p.join(
      getIt<FileStore>().docDir(documentId).path,
      'mask_${pageId}_${newId()}.png',
    );
    await File(out).parent.create(recursive: true);
    await File(mask).copy(out);
    return out;
  }

  Future<void> _customSize() async {
    final l = context.l10n;
    final w = TextEditingController(text: _size.widthMm.toStringAsFixed(0));
    final h = TextEditingController(text: _size.heightMm.toStringAsFixed(0));
    final picked = await showDialog<PhotoSize>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.photoCustomTitle),
        content: Row(
          children: [
            for (final (c, label) in [
              (w, l.photoWidthMm),
              (h, l.photoHeightMm),
            ]) ...[
              if (c == h) const SizedBox(width: Space.x3),
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(labelText: label),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final pw = double.tryParse(w.text);
              final ph = double.tryParse(h.text);
              if (pw == null ||
                  ph == null ||
                  pw < 15 ||
                  ph < 15 ||
                  pw > 120 ||
                  ph > 120) {
                return;
              }
              Navigator.of(ctx).pop(PhotoSize(pw, ph));
            },
            child: Text(l.commonDone),
          ),
        ],
      ),
    );
    w.dispose();
    h.dispose();
    if (picked != null && mounted) setState(() => _size = picked);
  }

  Future<void> _next([_After after = _After.preview]) async {
    final image = _image;
    final frame = _frame;
    final placement = _placement;
    if (image == null || frame == null || placement == null) return;
    setState(() => _saving = true);
    final edits = (widget.args.page?.edits ?? const PageEdits()).copyWith(
      crop: placement.cropFor(image, frame),
      quarterTurns: 0,
      filter: FilterType.original,
      outputAspect: _size.aspect,
      photoWidthMm: _size.widthMm,
      photoHeightMm: _size.heightMm,
      photoBackground: _segmentable ?? false
          ? _background
          : PhotoBackground.original,
      photoEnhance: _enhance,
      backgroundMaskPath: null,
    );
    // The mask serves the background and Enhance. Segment the crop itself
    // now: far sharper hair and ears than the whole-photo mask.
    var mask =
        (_segmentable ?? false) &&
            (_background != PhotoBackground.original ||
                _enhance != PhotoEnhance.off)
        ? _mask
        : null;
    if (mask != null) {
      mask =
          await getIt<BackgroundSegmenter>().maskFor(
            _photo,
            focus: edits.crop,
            coarse: mask,
          ) ??
          mask;
      if (!mounted) return;
    }
    final page = widget.args.page;
    if (page != null) {
      // Re-crop: same page, new frame; previews re-render.
      final keep =
          mask != null &&
          p.isWithin(getIt<FileStore>().docDir(page.documentId).path, mask);
      final updated = page.copyWith(
        edits: edits.copyWith(
          backgroundMaskPath: mask == null
              ? null
              : (keep
                    ? mask
                    : await _adoptMask(page.documentId, page.id, mask)),
        ),
        originalPath: _photo == widget.args.photoPath
            ? page.originalPath
            : _photo,
        processedPath: null,
        thumbPath: null,
        ocrText: null,
      );
      final r = await getIt<UpdatePages>()([updated]);
      if (!mounted) return;
      setState(() => _saving = false);
      if (r.isLeft()) {
        return context.showSnack(context.l10n.errorGeneric, error: true);
      }
      context.pop();
      return;
    }
    final addTo = widget.args.addToDocumentId;
    if (addTo != null) {
      // Round 10, P1-8: another person on the same sheet.
      final id = newId();
      final page = ScanPage(
        id: id,
        documentId: addTo,
        originalPath: _photo,
        edits: edits.copyWith(backgroundMaskPath: mask == null ? null : await _adoptMask(addTo, id, mask)),
        order: 1 << 20, // after the others
      );
      final r = await getIt<AddPages>()(addTo, [page]);
      if (!mounted) return;
      setState(() => _saving = false);
      if (r.isLeft()) return context.showSnack(context.l10n.errorGeneric, error: true);
      context.pop();
      return;
    }
    final r = await getIt<CreateDocument>()(
      mode: ScanMode.photo,
      pages: [
        ScanPage(
          id: newId(),
          documentId: '',
          originalPath: _photo,
          edits: edits,
          order: 0,
        ),
      ],
      title: context.l10n.photoDefaultTitle(dateStampText(DateTime.now())),
    );
    if (!mounted) return;
    final doc = r.toNullable();
    if (doc == null) {
      setState(() => _saving = false);
      return context.showSnack(
        failureMessage(context, r.getLeft().toNullable()),
        error: true,
      );
    }
    if (mask != null) {
      final saved = doc.pages.single;
      final kept = await _adoptMask(doc.id, saved.id, mask);
      await getIt<UpdatePages>()([
        saved.copyWith(edits: saved.edits.copyWith(backgroundMaskPath: kept)),
      ]);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // Round 10, P1-8: Preview opens the photo in the viewer; Print goes on
    // to the print sheet (Back from it lands on the viewer).
    final router = GoRouter.of(context)..go(Routes.home);
    unawaited(router.push(Routes.viewer(doc.id)));
    if (after == _After.print) unawaited(router.push(Routes.photoSheet(doc.id)));
  }

  /// A brand-new photo (not a re-crop, not another person for a sheet).
  bool get _isNew => widget.args.page == null && widget.args.addToDocumentId == null;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final sizes = [PhotoSize.passport, PhotoSize.twoByTwo];
    final custom = !sizes.contains(_size);
    return AppScaffold(
      topBar: AppTopBar(
        leading: TopBarLeading.close,
        title: l.photoTitle,
        subtitle: l.photoStepCrop,
        actions: [
          // Next = Preview (round 10, P1-8).
          TopBarTextAction(
            label: _isNew ? l.adjustNext : l.commonSave,
            onPressed: _placement == null || _saving ? null : _next,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: c.stage,
                  child: _loadFailed
                      ? _LoadFailed(onRetake: _retake)
                      : _image == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, box) {
                            final frame = _frameFor(box.biggest);
                            if (_frame != frame) {
                              final first = _placement == null;
                              _place(frame);
                              // The top bar and the button were built before
                              // this placement: rebuild them enabled (P1-3.5).
                              if (first) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) setState(() {});
                                });
                              }
                            }
                            final p = _placement!;
                            return GestureDetector(
                              onScaleStart: (d) {
                                _start = p;
                                _startFocal = d.localFocalPoint;
                              },
                              onScaleUpdate: (d) {
                                final s = _start;
                                if (s == null) return;
                                setState(() {
                                  _placement = s
                                      .transformed(
                                        factor: d.scale,
                                        focal: _startFocal,
                                        pan: d.localFocalPoint - _startFocal,
                                      )
                                      .clamp(_image!, frame);
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  Positioned(
                                    left: p.offset.dx,
                                    top: p.offset.dy,
                                    width: _image!.width * p.scale,
                                    height: _image!.height * p.scale,
                                    child: Image.file(
                                      File(_shown),
                                      key: ValueKey(_shown),
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                      cacheWidth: 1600,
                                      errorBuilder: (context, _, _) =>
                                          _LoadFailed(onRetake: _retake),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _GuidesPainter(
                                          frame,
                                          c.stage,
                                          c.accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _GuideLabel(
                                    text: l.photoTopOfHead,
                                    frame: frame,
                                    y: _GuidesPainter.topLine,
                                  ),
                                  _GuideLabel(
                                    text: l.photoChin,
                                    frame: frame,
                                    y: _GuidesPainter.chinLine,
                                  ),
                                  Positioned(
                                    left: Space.x4,
                                    right: Space.x4,
                                    bottom: Space.x2,
                                    child: Center(
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minHeight: 30,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: Space.x3,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.chip,
                                          borderRadius: Radii.pillR,
                                        ),
                                        child: FitText(
                                          l.photoHint,
                                          style: context.text.labelMedium
                                              ?.copyWith(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              // At most half the screen, scrolling inside at large fonts,
              // so the photo always has room.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.x4,
                          14,
                          Space.x4,
                          18,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Adding a person: the sheet's size, not a choice.
                            if (widget.args.addToDocumentId == null) ...[
                            SectionLabel(
                              l.photoSizeLabel,
                              padding: const EdgeInsets.only(bottom: Space.x2),
                            ),
                            Row(
                              children: [
                                for (final (i, label) in [
                                  l.photoSize35x45,
                                  l.photoSize2x2,
                                  if (custom)
                                    '${_size.widthMm.round()} × ${_size.heightMm.round()} mm'
                                  else
                                    l.photoSizeCustom,
                                ].indexed) ...[
                                  if (i > 0) const SizedBox(width: Space.x2),
                                  Expanded(
                                    child: _Choice(
                                      label: label,
                                      selected:
                                          i ==
                                          (custom ? 2 : sizes.indexOf(_size)),
                                      onTap: () => i == 2
                                          ? unawaited(_customSize())
                                          : setState(() => _size = sizes[i]),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            ],
                            // White / Light blue only where segmentation works.
                            if (_segmentable ?? true) ...[
                              const SizedBox(height: Space.x3),
                              SectionLabel(
                                l.photoBackgroundLabel,
                                padding: const EdgeInsets.only(
                                  bottom: Space.x2,
                                ),
                              ),
                              // Round 10, P1-7: named swatches, the usual
                              // light blues among them.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final bg in PhotoBackgrounds.shown)
                                    Expanded(
                                      child: _Swatch(
                                      label: switch (bg) {
                                        PhotoBackground.original => l.photoBackgroundOriginal,
                                        PhotoBackground.white => l.photoBackgroundWhite,
                                        PhotoBackground.offWhite => l.photoBackgroundOffWhite,
                                        PhotoBackground.paleBlue => l.photoBackgroundLightBlue,
                                        PhotoBackground.skyBlue => l.photoBackgroundSkyBlue,
                                        PhotoBackground.darkBlue => l.photoBackgroundDarkBlue,
                                      },
                                      color: switch (PhotoBackgrounds.argb(bg)) {
                                        null => null,
                                        final v => Color(v),
                                      },
                                      selected: _background == bg,
                                      // Ready once the person is found.
                                      loading: bg != PhotoBackground.original && _segmentable == null,
                                      onTap: bg == PhotoBackground.original || (_segmentable ?? false)
                                          ? () => _choose(background: bg)
                                          : null,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            // Light, colour and skin (works without
                            // segmentation too).
                            const SizedBox(height: Space.x3),
                            SectionLabel(
                              l.photoEnhanceLabel,
                              padding: const EdgeInsets.only(bottom: Space.x2),
                            ),
                            Row(
                              children: [
                                for (final (i, e)
                                    in PhotoEnhance.values.indexed) ...[
                                  if (i > 0) const SizedBox(width: Space.x2),
                                  Expanded(
                                    child: _Choice(
                                      label: switch (e) {
                                        PhotoEnhance.off => l.photoEnhanceOff,
                                        PhotoEnhance.natural =>
                                          l.photoEnhanceNatural,
                                        PhotoEnhance.smooth =>
                                          l.photoEnhanceSmooth,
                                      },
                                      selected: _enhance == e,
                                      onTap: () => _choose(enhance: e),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: Space.x1),
                            Text(
                              switch (_enhance) {
                                PhotoEnhance.off => l.photoEnhanceOffHint,
                                PhotoEnhance.natural =>
                                  l.photoEnhanceNaturalHint,
                                PhotoEnhance.smooth => l.photoEnhanceSmoothHint,
                              },
                              style: context.text.bodySmall?.copyWith(
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(height: Space.x3),
                            Row(
                              children: [
                                Expanded(
                                  child: SecondaryButton(
                                    label: l.photoRetake,
                                    dense: true,
                                    onPressed: _saving ? null : _retake,
                                  ),
                                ),
                                // Round 10, P1-8: a new photo: Retake · Preview ·
                                // Print; editing or adding one: Retake · Save.
                                if (_isNew) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SecondaryButton(
                                      label: l.photoPreview,
                                      dense: true,
                                      onPressed: _placement == null || _saving ? null : _next,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: _isNew ? 1 : 2,
                                  child: PrimaryButton(
                                    label: _isNew ? l.viewerPrint : l.commonSave,
                                    dense: true,
                                    loading: _saving,
                                    onPressed: _placement == null ? null : () => _next(_After.print),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dims outside the frame; draws the frame, the face oval and the top-of-head
/// and chin lines. ICAO: the head (chin to crown) is about 70–80 % of the
/// photo height, its top 8–12 % from the top edge.
class _GuidesPainter extends CustomPainter {
  _GuidesPainter(this.frame, this.scrim, this.accent);

  final Rect frame;
  final Color scrim;
  final Color accent;

  static const topLine = 0.10;
  static const chinLine = 0.84;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(outside, Paint()..color = scrim.withValues(alpha: 0.72));
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(frame, line);
    final top = frame.top + frame.height * topLine;
    final chin = frame.top + frame.height * chinLine;
    final guide = Paint()
      ..color = accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final y in [top, chin]) {
      canvas.drawLine(
        Offset(frame.left + 6, y),
        Offset(frame.right - 6, y),
        guide,
      );
    }
    final ovalW = math.min(frame.width * 0.62, (chin - top) * 0.78);
    canvas.drawOval(
      Rect.fromLTRB(
        frame.center.dx - ovalW / 2,
        top,
        frame.center.dx + ovalW / 2,
        chin,
      ),
      guide,
    );
  }

  @override
  bool shouldRepaint(_GuidesPainter old) =>
      old.frame != frame || old.accent != accent || old.scrim != scrim;
}

/// "Top of head" / "Chin", right-aligned inside the frame just above its
/// line.
class _GuideLabel extends StatelessWidget {
  const _GuideLabel({required this.text, required this.frame, required this.y});
  final String text;
  final Rect frame;
  final double y;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: frame.left + 8,
      width: frame.width - 16,
      top: frame.top + frame.height * y - 20,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerRight,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xA60F1012),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                maxLines: 1,
                style: context.text.labelSmall?.copyWith(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo couldn't be opened: say so, and offer Retake.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetake});
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.photoLoadFailed,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.x3),
            SecondaryButton(
              label: l.photoRetake,
              expand: false,
              onPressed: onRetake,
            ),
          ],
        ),
      ),
    );
  }
}

/// A choice in the bottom panel (photo size, background), artboard
/// *Passport photo · crop*: accent border and tint when selected.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? c.accent : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x2,
              vertical: 6,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FitText(
                    label,
                    // Two lines at the largest font ("Light / blue").
                    maxLines: 2,
                    style: context.text.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: enabled ? c.text : c.muted,
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

/// A background colour: a round swatch with its name under it (round 10,
/// P1-7). Original shows the photo's own background as a striped circle.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color, required this.selected, required this.onTap, this.loading = false});
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2.5),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color ?? c.surface2,
                      border: Border.all(color: c.borderStrong),
                    ),
                    child: loading
                        ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 1.6))
                        : color == null
                        ? Center(child: AppIcon(AppIcons.portrait, size: 18, color: c.muted))
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                FitText(
                  label,
                  maxLines: 2,
                  style: context.text.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: enabled ? c.text : c.muted,
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
