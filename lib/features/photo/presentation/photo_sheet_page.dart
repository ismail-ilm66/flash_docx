import 'dart:async';
import 'dart:io';

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
import 'package:flash_dox/features/photo/domain/photo_frame.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;

/// Print resolution for the photos on the sheet.
const _dpi = 300;

/// Passport photo, step 2 (feature 5, artboard *Print sheet*): the photo at
/// real size on A4 or 4 × 6 in, 4 · 8 · 12 · 16 · Full copies, dashed cut
/// lines, then a PDF to share or save.
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

  /// The photo rendered at print size; also the preview.
  String? _photo;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
    final page = doc.cover!;
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
    if (mounted) setState(() => _photo = out);
  }

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
    final doc = _doc;
    final photo = _photo;
    if (doc == null || photo == null) return;
    setState(() => _working = true);
    final l = context.l10n;
    try {
      final pdf = await getIt<PdfBuilder>().photoSheet(
        photoPath: photo,
        items: PhotoSheetCalculator.layout(_spec),
        paper: _paper,
        cutLines: _cutLines,
        title: doc.title,
        outputPath: getIt<FileStore>().exportPath('${doc.title.fileSafe}.pdf'),
      );
      final Either<Object, Object?> r = share
          ? await getIt<ShareService>().shareFiles([pdf], subject: doc.title)
          : await getIt<SaveService>().saveFileWithDialog(pdf);
      if (!mounted) return;
      r.fold(
        (f) {
          if (f is! CancelledFailure) {
            context.showSnack(l.errorPdf, error: true);
          }
        },
        (_) {
          unawaited(getIt<LogActivity>()(doc.id, ActivityType.photoSheet));
          if (!share) context.showSnack(l.shareSaved);
        },
      );
    } on Object {
      if (mounted) context.showSnack(l.errorPdf, error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final items = PhotoSheetCalculator.layout(_spec);
    final counts = _counts;
    return AppScaffold(
      topBar: AppTopBar(
        title: l.photoSheetTitle,
        subtitle: _doc == null ? null : l.photoStepSheet(_sizeLabel(_size)),
      ),
      body: Stack(
        children: [
          _Body(
            children: [
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
                                            child: CircularProgressIndicator(),
                                          )
                                        : Stack(
                                            children: [
                                              for (final it in items)
                                                Positioned(
                                                  left: it.x * k,
                                                  top: it.y * k,
                                                  width: it.w * k,
                                                  height: it.h * k,
                                                  child: DecoratedBox(
                                                    position: DecorationPosition
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
                                                      File(_photo!),
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
                                // The last choice is always a full sheet.
                                label: n == counts.last ? l.photoFull(n) : '$n',
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
                            for (final (i, p) in PhotoPaper.values.indexed) ...[
                              if (i > 0) const SizedBox(width: Space.x2),
                              Expanded(
                                child: OptionCard(
                                  height: 56,
                                  title: _paperName(context, p),
                                  subtitle: l.photoUpTo(
                                    PhotoSheetCalculator.full(
                                      _size.widthMm,
                                      _size.heightMm,
                                      p,
                                    ),
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
                                label: l.photoSharePdf,
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
  const _Body({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    if (!large) {
      return Column(children: [for (final c in children) c is _StageSlot ? Expanded(child: c) : c]);
    }
    return SingleChildScrollView(
      child: Column(children: [for (final c in children) c is _StageSlot ? SizedBox(height: 360, child: c) : c]),
    );
  }
}
