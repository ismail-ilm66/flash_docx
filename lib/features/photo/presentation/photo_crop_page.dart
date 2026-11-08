import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/photo/domain/photo_frame.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/signature/presentation/pages/sign_document_page.dart'
    show dateStampText;
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// What the crop screen works on: a fresh photo, or a saved passport photo
/// being re-cropped.
class PhotoCropArgs {
  const PhotoCropArgs({required this.photoPath, this.page});

  final String photoPath;

  /// Set when re-cropping a saved photo.
  final ScanPage? page;
}

/// Tools › Passport photo: take or pick one photo, then crop it.
Future<void> startPassportPhoto(BuildContext context) async {
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
  await context.push(Routes.photoCrop, extra: PhotoCropArgs(photoPath: path));
}

Future<String?> _pickPhoto(BuildContext context, {required bool camera}) async {
  if (camera) {
    final shot = await context.push<RetakeShot>(
      Routes.camera,
      extra: const CameraArgs(retake: true, mode: ScanMode.document),
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

  // Gesture state.
  PhotoPlacement? _start;
  Offset _startFocal = Offset.zero;

  PhotoSize _initialSize() {
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
    final s = await getIt<ImageProcessor>().imageSize(_photo);
    if (!mounted) return;
    setState(() {
      _image = Size(s.width.toDouble(), s.height.toDouble());
      _placement = null; // placed on the next layout
    });
  }

  /// Fits the frame into the stage, leaving room for the guide labels.
  Rect _frameFor(Size stage) {
    const pad = 36.0;
    final maxW = stage.width - pad * 2;
    final maxH = stage.height - pad * 2;
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
    final keepOld = _placement == null && saved != null && _frame == null;
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
    });
    await _loadSize();
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

  Future<void> _next() async {
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
    );
    final page = widget.args.page;
    if (page != null) {
      // Re-crop: same page, new frame; previews re-render.
      final updated = page.copyWith(
        edits: edits,
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
    setState(() => _saving = false);
    r.fold(
      (f) => context.showSnack(failureMessage(context, f), error: true),
      (doc) {
        context
          ..go(Routes.home)
          ..push(Routes.viewer(doc.id))
          ..push(Routes.photoSheet(doc.id));
      },
    );
  }

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
          TopBarTextAction(
            label: l.adjustNext,
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
                  child: _image == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, box) {
                            final frame = _frameFor(box.biggest);
                            if (_frame != frame) _place(frame);
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
                                      File(_photo),
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                      cacheWidth: 1600,
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
              DecoratedBox(
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
                        SectionLabel(
                          l.photoSizeLabel,
                          padding: const EdgeInsets.only(bottom: Space.x2),
                        ),
                        SegmentedPills<int>(
                          values: const [0, 1, 2],
                          selected: custom ? 2 : sizes.indexOf(_size),
                          height: 40,
                          labelOf: (i) => switch (i) {
                            0 => l.photoSize35x45,
                            1 => l.photoSize2x2,
                            _ =>
                              custom
                                  ? '${_size.widthMm.round()} × ${_size.heightMm.round()} mm'
                                  : l.photoSizeCustom,
                          },
                          onChanged: (i) {
                            if (i == 2) {
                              unawaited(_customSize());
                            } else {
                              setState(() => _size = sizes[i]);
                            }
                          },
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
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: PrimaryButton(
                                label: widget.args.page == null
                                    ? l.photoMakeSheet
                                    : l.commonSave,
                                dense: true,
                                loading: _saving,
                                onPressed: _placement == null ? null : _next,
                              ),
                            ),
                          ],
                        ),
                      ],
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
