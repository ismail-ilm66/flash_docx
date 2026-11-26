import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/extensions/string_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/photo/domain/photo_frame.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;

/// Print resolution for the photos on the sheet.
const _dpi = 300;

/// Passport photo, step 2 (feature 5, artboard *Print sheet*): the photo at
/// real size on A4 or 4 × 6 in, 4 · 8 · 12 · 16 copies, dashed cut lines,
/// then a PDF to share or save. Or one photo on its own (JPG / PNG, pixel
/// size, max file size) for forms that want an upload.
class PhotoSheetPage extends StatefulWidget {
  const PhotoSheetPage({required this.documentId, super.key});

  final String documentId;

  @override
  State<PhotoSheetPage> createState() => _PhotoSheetPageState();
}

class _PhotoSheetPageState extends State<PhotoSheetPage> {
  ScanDocument? _doc;
  PhotoPaper _paper = PhotoPaper.a4;
  int? _count;
  bool _cutLines = true;
  bool _single = false;

  /// Single photo export; made the first time that mode opens.
  ExportBloc? _exportBloc;

  /// Each person's photo rendered at print size (round 10, P1-8: several
  /// people can share a sheet); also the preview. [_photo] is the first.
  List<String>? _photos;
  String? get _photo => _photos?.firstOrNull;
  bool _working = false;

  /// Round 10, P1-8: the sheet as a PDF (to print, exact size at 100 %) or
  /// a JPG at 300 DPI (photo shop / WhatsApp).
  bool _jpg = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_exportBloc?.close());
    super.dispose();
  }

  void _setSingle(bool single) {
    final doc = _doc;
    if (single && _exportBloc == null && doc != null) {
      getIt<RewardGate>().preload();
      _exportBloc = getIt<ExportBloc>(param1: doc)
        ..add(const ExportSheetOpened());
    }
    setState(() => _single = single);
  }

  ScanPage? get _page => _doc?.cover;

  PhotoSize get _size {
    final e = _page?.edits;
    return e?.photoWidthMm != null && e?.photoHeightMm != null
        ? PhotoSize(e!.photoWidthMm!, e.photoHeightMm!)
        : PhotoSize.passport;
  }

  Future<void> _load() async {
    final doc = (await getIt<GetDocument>()(widget.documentId)).toNullable();
    if (!mounted || doc == null || doc.cover == null) return;
    setState(() => _doc = doc);
    final photos = <String>[];
    for (final page in doc.sortedPages) {
      final out = getIt<FileStore>().exportPath(
        'photo_${page.id}_${Object.hash(page.originalPath, page.edits)}.jpg',
      );
      if (!File(out).existsSync()) {
        await getIt<ImageProcessor>().renderPhoto(
          page.originalPath,
          page.edits,
          widthMm: _size.widthMm,
          heightMm: _size.heightMm,
          dpi: _dpi,
          outputPath: out,
        );
      }
      photos.add(out);
    }
    if (mounted) setState(() => _photos = photos);
  }

  /// Which person's photo each place on the sheet shows.
  List<int> _photoOf(int places) => PhotoSheetCalculator.assignPeople(places, _photos?.length ?? 1);

  List<int> get _counts =>
      PhotoSheetCalculator.counts(_size.widthMm, _size.heightMm, _paper);

  int get _effectiveCount {
    final counts = _counts;
    if (counts.isEmpty) return 0;
    final want = _count ?? (counts.contains(12) ? 12 : counts.last);
    return counts.contains(want) ? want : counts.last;
  }

  PrintItemSpec get _spec => PrintItemSpec(
    widthMm: _size.widthMm,
    heightMm: _size.heightMm,
    count: _effectiveCount,
    paper: _paper,
    cutLines: _cutLines,
  );

  String _paperName(BuildContext context, PhotoPaper p) => p == PhotoPaper.a4
      ? context.l10n.photoPaperA4
      : context.l10n.photoPaper4x6;

  String _sizeLabel(PhotoSize s) => s == PhotoSize.twoByTwo
      ? context.l10n.photoSize2x2
      : '${_mm(s.widthMm)} × ${_mm(s.heightMm)} mm';

  static String _mm(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  Future<void> _export({required bool share}) async {
    if (!share && !await readyToSave(context)) return;
    if (!mounted) return;
    final doc = _doc;
    final photos = _photos;
    if (doc == null || photos == null) return;
    setState(() => _working = true);
    final l = context.l10n;
    try {
      final items = PhotoSheetCalculator.layout(_spec);
      final File file;
      if (_jpg) {
        file = File(
          await getIt<ImageProcessor>().renderPhotoSheet(
            photoPaths: photos,
            photoOf: _photoOf(items.length),
            items: [for (final it in items) (x: it.x, y: it.y, w: it.w, h: it.h)],
            paperWidthMm: _paper.widthMm,
            paperHeightMm: _paper.heightMm,
            cutLines: _cutLines,
            outputPath: getIt<FileStore>().exportPath('${doc.title.fileSafe}.jpg'),
          ),
        );
      } else {
        file = await getIt<PdfBuilder>().photoSheet(
          photoPaths: photos,
          photoOf: _photoOf(items.length),
          items: items,
          paper: _paper,
          cutLines: _cutLines,
          title: doc.title,
          outputPath: getIt<FileStore>().exportPath('${doc.title.fileSafe}.pdf'),
        );
      }
      final Either<Object, Object?> r = share
          ? await getIt<ShareService>().shareFiles([file], subject: doc.title)
          : _jpg
          ? await getIt<SaveService>().saveImages([file])
          : await getIt<SaveService>().saveFileWithDialog(file);
      if (!mounted) return;
      r.fold(
        (f) {
          if (f is! CancelledFailure) {
            context.showSnack(l.errorPdf, error: true);
          }
        },
        (_) {
          unawaited(getIt<LogActivity>()(doc.id, ActivityType.photoSheet));
          if (!share) showSaved(context);
        },
      );
    } on Object {
      if (mounted) context.showSnack(l.errorPdf, error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// The photo on its own above the share options (JPG / PNG, image size,
  /// max file size, Save / Share).
  List<Widget> _singleMode(BuildContext context) {
    final c = context.colors;
    final size = _size;
    return [
      _StageSlot(
        child: ColoredBox(
          color: c.stage,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x6,
              Space.x4,
              Space.x6,
              Space.x2,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: size.widthMm / size.heightMm,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: _photo == null
                            ? const Center(child: CircularProgressIndicator())
                            : Image.file(
                                File(_photo!),
                                fit: BoxFit.fill,
                                cacheWidth: 600,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.x2),
                Text(
                  context.l10n.photoSingleCaption,
                  textAlign: TextAlign.center,
                  style: context.text.labelSmall?.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_exportBloc != null)
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 18),
              child: BlocProvider.value(
                value: _exportBloc!,
                child: const SharePanel(inline: true),
              ),
            ),
          ),
        ),
    ];
  }

  /// The sheet at its paper shape, photos and cut lines.
  Widget _sheetView(List<PlacedItem> items) => AspectRatio(
      aspectRatio: _paper.widthMm / _paper.heightMm,
      child: LayoutBuilder(
        builder: (context, box) {
          final k = box.maxWidth / _paper.widthMm;
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: _photo == null
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : Stack(
                    children: [
                      for (final (i, it) in items.indexed)
                        Positioned(
                          left: it.x * k,
                          top: it.y * k,
                          width: it.w * k,
                          height: it.h * k,
                          child: DecoratedBox(
                            position:
                                DecorationPosition
                                    .foreground,
                            decoration: BoxDecoration(
                              border: _cutLines
                                  ? Border.all(
                                      color:
                                          const Color(
                                            0xFF9FA3AA,
                                          ),
                                      width: 0.6,
                                    )
                                  : null,
                            ),
                            child: Image.file(
                              File(_photos![_photoOf(items.length)[i]]),
                              fit: BoxFit.fill,
                              cacheWidth: 240,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );

  /// Round 11b, H5: tap the preview for a full-screen one with pinch zoom.
  void _openFull(List<PlacedItem> items) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: InteractiveViewer(
            maxScale: 6,
            child: Center(child: Padding(padding: const EdgeInsets.all(Space.x3), child: _sheetView(items))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final items = PhotoSheetCalculator.layout(_spec);
    final counts = _counts;
    return AppScaffold(
      topBar: AppTopBar(
        title: _single ? l.photoModeSingle : l.photoSheetTitle,
        subtitle: _doc == null ? null : l.photoStepSheet(_sizeLabel(_size)),
      ),
      body: Stack(
        children: [
          _Body(
            scroll: _single,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  Space.x2,
                  Space.x4,
                  Space.x2,
                ),
                child: SegmentedPills<bool>(
                  values: const [false, true],
                  selected: _single,
                  labelOf: (v) => v ? l.photoModeSingle : l.photoModeSheet,
                  onChanged: _doc == null ? (_) {} : _setSingle,
                ),
              ),
              if (_single)
                ..._singleMode(context)
              else
                _StageSlot(
                  child: ColoredBox(
                    color: c.stage,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.x4,
                        Space.x4,
                        Space.x4,
                        Space.x2,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: GestureDetector(
                                onTap: () => _openFull(items),
                                child: _sheetView(items),
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.x2),
                          Text(
                            l.photoSheetCaption(
                              _paperName(context, _paper),
                              items.length,
                            ),
                            textAlign: TextAlign.center,
                            style: context.text.labelSmall?.copyWith(
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_single)
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
                            l.photoCopies,
                            padding: const EdgeInsets.only(bottom: Space.x2),
                          ),
                          Wrap(
                            spacing: Space.x2,
                            runSpacing: Space.x2,
                            children: [
                              for (final n in counts)
                                OptionChip(
                                  label: '$n',
                                  selected: n == _effectiveCount,
                                  onTap: () => setState(() => _count = n),
                                ),
                            ],
                          ),
                          const SizedBox(height: Space.x3),
                          SectionLabel(
                            l.photoPaperLabel,
                            padding: const EdgeInsets.only(bottom: Space.x2),
                          ),
                          Row(
                            children: [
                              for (final (i, p)
                                  in PhotoPaper.values.indexed) ...[
                                if (i > 0) const SizedBox(width: Space.x2),
                                Expanded(
                                  child: OptionCard(
                                    height: 56,
                                    title: _paperName(context, p),
                                    // The most copies offered, not the
                                    // most that fit (no "Full" choice).
                                    subtitle: l.photoUpTo(
                                      PhotoSheetCalculator.counts(
                                        _size.widthMm,
                                        _size.heightMm,
                                        p,
                                      ).fold(0, max),
                                    ),
                                    selected: _paper == p,
                                    onTap: () => setState(() => _paper = p),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: Space.x2),
                          Row(
                            children: [
                              Switch.adaptive(
                                value: _cutLines,
                                onChanged: (v) => setState(() => _cutLines = v),
                              ),
                              const SizedBox(width: Space.x1),
                              Expanded(
                                child: Text(
                                  l.photoCutLines,
                                  style: context.text.labelMedium,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            margin: const EdgeInsets.only(
                              top: Space.x1,
                              bottom: Space.x3,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.x3,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppIcon(
                                  AppIcons.print,
                                  size: 18,
                                  color: c.accentText,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    l.photoPrintTip,
                                    style: context.text.bodySmall?.copyWith(
                                      height: 1.45,
                                      color: c.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Round 10, P1-8: PDF to print, or a picture for a
                          // photo shop.
                          SectionLabel(l.shareFormat, padding: const EdgeInsets.only(bottom: Space.x2)),
                          Row(
                            children: [
                              for (final (i, jpg) in const [false, true].indexed) ...[
                                if (i > 0) const SizedBox(width: Space.x2),
                                Expanded(
                                  child: OptionCard(
                                    height: 56,
                                    title: jpg ? l.shareJpg : l.sharePdf,
                                    subtitle: jpg ? l.photoSheetJpgHint : l.photoSheetPdfHint,
                                    selected: _jpg == jpg,
                                    onTap: () => setState(() => _jpg = jpg),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: Space.x3),
                          Row(
                            children: [
                              Expanded(
                                child: SecondaryButton(
                                  label: l.shareSaveToPhone,
                                  icon: AppIcons.save,
                                  dense: true,
                                  onPressed: _photo == null || _working
                                      ? null
                                      : () => _export(share: false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PrimaryButton(
                                  label: _jpg ? l.shareButtonFormat(l.shareJpg) : l.photoSharePdf,
                                  icon: AppIcons.share,
                                  dense: true,
                                  loading: _working,
                                  onPressed: _photo == null
                                      ? null
                                      : () => _export(share: true),
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

/// Marks the sheet preview inside [_Body].
class _StageSlot extends StatelessWidget {
  const _StageSlot({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Normal fonts: the preview fills what the controls leave. Large fonts:
/// the controls need most of a small screen, so the page scrolls and the
/// preview gets a fixed height (like Print).
class _Body extends StatelessWidget {
  const _Body({required this.children, this.scroll = false});
  final List<Widget> children;

  /// Always scroll (the single photo's options are taller than a sheet's).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    // Round 11b, H5: the sheet preview gets about 55 % of the screen
    // height (it was ~100 px wide); the options scroll under it.
    final stage = MediaQuery.sizeOf(context).height * (scroll ? 0.4 : 0.55);
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final c in children) c is _StageSlot ? SizedBox(height: stage, child: c) : c,
        ],
      ),
    );
  }
}
