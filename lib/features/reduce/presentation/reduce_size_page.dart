import 'dart:io';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/core/utils/bytes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flash_dox/features/reduce/data/reduce_service.dart';
import 'package:flash_dox/features/reduce/domain/reduce_options.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// What Reduce size works on (round 11, section F).
sealed class ReduceSource {
  const ReduceSource();
}

class ReduceImages extends ReduceSource {
  const ReduceImages(this.paths);
  final List<String> paths;
}

/// Any PDF on the phone (a copy from the system file picker).
class ReducePdf extends ReduceSource {
  const ReducePdf(this.path);
  final String path;
}

class ReduceDocument extends ReduceSource {
  const ReduceDocument(this.document);
  final ScanDocument document;
}

/// Home › Tools › Reduce size: Choose PDF · Choose images · a recent Flash
/// Dox document, then the Reduce size screen.
Future<void> startReduceSize(BuildContext context) async {
  final source = await AppBottomSheet.show<ReduceSource>(context, builder: (_) => const _ReducePicker());
  if (source == null || !context.mounted) return;
  await context.push(Routes.reduce, extra: source);
}

class _ReducePicker extends StatelessWidget {
  const _ReducePicker();

  Future<void> _pdf(BuildContext context) async {
    final r = await getIt<ImportService>().pdfFromFiles();
    if (!context.mounted) return;
    r.fold(
      (f) {
        if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      },
      (path) => Navigator.of(context).pop(ReducePdf(path)),
    );
  }

  Future<void> _images(BuildContext context) async {
    final r = await getIt<ImportService>().fromGallery();
    if (!context.mounted) return;
    r.fold(
      (f) {
        if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      },
      (paths) => Navigator.of(context).pop(ReduceImages(paths)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppBottomSheet(
      title: l.reducePickTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PrimaryButton(label: l.reduceChoosePdf, icon: AppIcons.pdf, dense: true, onPressed: () => _pdf(context)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(label: l.reduceChooseImages, icon: AppIcons.gallery, dense: true, onPressed: () => _images(context)),
              ),
            ],
          ),
          const SizedBox(height: Space.x5),
          SectionLabel(l.pickOrDocument, padding: const EdgeInsets.only(bottom: Space.x1)),
          StreamBuilder<List<ScanDocument>>(
            stream: getIt<WatchDocuments>()(),
            builder: (context, snap) {
              final docs = [...?snap.data]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
              return Column(
                children: [
                  for (final d in docs.take(20))
                    DocumentTile(
                      document: d,
                      compact: true,
                      onTap: () => Navigator.of(context).pop(ReduceDocument(d)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Reduce size (round 11, section F): the size limit (and for images the
/// pixel size and format), Reduce, then "2.4 MB → 186 KB · 3 pages" with
/// Save to phone · Share. The original is never changed.
class ReduceSizePage extends StatefulWidget {
  const ReduceSizePage({required this.source, super.key});

  final ReduceSource source;

  @override
  State<ReduceSizePage> createState() => _ReduceSizePageState();
}

class _ReduceSizePageState extends State<ReduceSizePage> {
  int _maxBytes = 200 * 1000;
  PixelSize _pixels = const PixelSize.original();
  ReduceFormat _format = ReduceFormat.jpg;
  bool _working = false;
  ReduceResult? _result;
  bool _warned = false;

  bool get _images => widget.source is ReduceImages;

  String get _name => switch (widget.source) {
    ReduceImages(:final paths) => paths.length == 1 ? p.basename(paths.single) : context.l10n.reduceImages(paths.length),
    ReducePdf(:final path) => p.basename(path),
    ReduceDocument(:final document) => document.title,
  };

  Future<void> _reduce({bool anyway = false}) async {
    final l = context.l10n;
    // Other PDFs become pictures: say so once, before reducing.
    if (widget.source is ReducePdf && !_warned) {
      final ok = await AppDialog.confirm(
        context,
        title: l.reducePdfWarningTitle,
        body: l.reducePdfWarningBody,
        confirmLabel: l.reduceContinue,
        cancelLabel: l.commonCancel,
      );
      if (!ok || !mounted) return;
      _warned = true;
    }
    setState(() {
      _working = true;
      _result = null;
    });
    final svc = getIt<ReduceService>();
    final r = switch (widget.source) {
      ReduceImages(:final paths) => await svc.images(paths, maxBytes: _maxBytes, size: _pixels, format: _format),
      ReducePdf(:final path) => await svc.pdf(path, maxBytes: _maxBytes, anyway: anyway),
      ReduceDocument(:final document) => await svc.document(document, maxBytes: _maxBytes, anyway: anyway),
    };
    if (!mounted) return;
    setState(() => _working = false);
    r.fold(
      (f) => context.showSnack(failureMessage(context, f), error: true),
      (res) => setState(() => _result = res),
    );
  }

  Future<void> _save() async {
    final res = _result;
    if (res == null) return;
    final files = [for (final f in res.files) File(f)];
    final svc = getIt<SaveService>();
    final pdf = files.length == 1 && files.single.path.endsWith('.pdf');
    final r = pdf ? (await svc.saveFileWithDialog(files.single)).map((_) => unit) : await svc.saveImages(files);
    if (!mounted) return;
    r.fold(
      (f) {
        if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      },
      (_) => context.showSnack(context.l10n.shareSaved),
    );
  }

  Future<void> _share() async {
    final res = _result;
    if (res == null) return;
    final r = await getIt<ShareService>().shareFiles([for (final f in res.files) File(f)]);
    if (!mounted) return;
    r.fold((f) {
      if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
    }, (_) {});
  }

  Future<void> _customKb() async {
    final l = context.l10n;
    final ctrl = TextEditingController(text: '${_maxBytes ~/ 1000}');
    final kb = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.reduceCustomKbTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'KB'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.commonCancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctrl.text)), child: Text(l.commonOk)),
        ],
      ),
    );
    ctrl.dispose();
    if (kb != null && kb > 0 && mounted) setState(() => _maxBytes = kb * 1000);
  }

  Future<void> _customPixels() async {
    final l = context.l10n;
    final w = TextEditingController(text: '${_pixels.width ?? 1000}');
    final h = TextEditingController(text: '${_pixels.height ?? 1000}');
    var keep = !_pixels.exact || _pixels.isOriginal;
    final picked = await showDialog<PixelSize>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(l.reducePixels),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: w,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: l.reduceWidth, suffixText: 'px'),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: Space.x2), child: Text('×')),
                  Expanded(
                    child: TextField(
                      controller: h,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: l.reduceHeight, suffixText: 'px'),
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: keep,
                onChanged: (v) => setD(() => keep = v),
                title: Text(l.reduceKeepShape),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.commonCancel)),
            TextButton(
              onPressed: () {
                final ww = int.tryParse(w.text) ?? 0;
                final hh = int.tryParse(h.text) ?? 0;
                Navigator.of(ctx).pop(ww > 0 && hh > 0 ? PixelSize.box(ww, hh, exact: !keep) : null);
              },
              child: Text(l.commonOk),
            ),
          ],
        ),
      ),
    );
    w.dispose();
    h.dispose();
    if (picked != null && mounted) setState(() => _pixels = picked);
  }

  String _pixelLabel(PixelSize s) {
    final l = context.l10n;
    if (s.isOriginal) return l.reduceOriginal;
    if (s.longSide != null) return l.reduceLongSide(s.longSide!);
    return '${s.width}×${s.height}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final res = _result;
    final custom = !reduceSizePresets.contains(_maxBytes);
    final customPixels = !PixelSize.presets.contains(_pixels);
    Widget chips<T>(List<T> values, T selected, String Function(T) label, void Function(T) pick, {VoidCallback? onCustom, bool customOn = false, String? customLabel}) => Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: [
        for (final v in values)
          ChoiceChip(label: Text(label(v)), selected: v == selected && !customOn, onSelected: _working ? null : (_) => pick(v)),
        if (onCustom != null)
          ChoiceChip(label: Text(customLabel ?? l.reduceCustom), selected: customOn, onSelected: _working ? null : (_) => onCustom()),
      ],
    );
    return AppScaffold(
      topBar: AppTopBar(title: l.reduceTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
        children: [
          Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(l.reduceOriginalKept, style: context.text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: Space.x5),
          SectionLabel(_images ? l.reduceMaxSizeEach : l.reduceMaxSize, padding: const EdgeInsets.only(bottom: Space.x2)),
          chips<int>(
            reduceSizePresets,
            _maxBytes,
            formatBytes,
            (v) => setState(() => _maxBytes = v),
            onCustom: _customKb,
            customOn: custom,
            customLabel: custom ? formatBytes(_maxBytes) : null,
          ),
          if (_images) ...[
            const SizedBox(height: Space.x5),
            SectionLabel(l.reducePixels, padding: const EdgeInsets.only(bottom: Space.x2)),
            chips<PixelSize>(
              PixelSize.presets,
              _pixels,
              _pixelLabel,
              (v) => setState(() => _pixels = v),
              onCustom: _customPixels,
              customOn: customPixels,
              customLabel: customPixels ? _pixelLabel(_pixels) : null,
            ),
            const SizedBox(height: Space.x5),
            SectionLabel(l.reduceFormat, padding: const EdgeInsets.only(bottom: Space.x2)),
            chips<ReduceFormat>(ReduceFormat.values, _format, (f) => f.extension.toUpperCase(), (v) => setState(() => _format = v)),
          ],
          const SizedBox(height: Space.x6),
          PrimaryButton(label: _working ? l.reduceWorking : l.reduceGo, onPressed: _working ? null : _reduce),
          if (_working) const Padding(padding: EdgeInsets.only(top: Space.x4), child: Center(child: CircularProgressIndicator())),
          if (res != null) ...[
            const SizedBox(height: Space.x6),
            Container(
              padding: const EdgeInsets.all(Space.x4),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${l.reduceBeforeAfter(formatBytes(res.bytesBefore), formatBytes(res.bytesAfter))} · '
                    '${_images ? l.reduceImages(res.count) : l.reducePages(res.count)}',
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (!res.fits) ...[
                    const SizedBox(height: Space.x2),
                    Text(l.reduceSmallest(formatBytes(res.bytesAfter)), style: context.text.bodyMedium?.copyWith(color: c.danger)),
                  ],
                  const SizedBox(height: Space.x4),
                  if (res.files.isEmpty)
                    SecondaryButton(label: l.reduceSaveAnyway, onPressed: () => _reduce(anyway: true))
                  else
                    Row(
                      children: [
                        Expanded(child: SecondaryButton(label: l.shareSaveToPhone, icon: AppIcons.save, onPressed: _save)),
                        const SizedBox(width: Space.x3),
                        Expanded(child: PrimaryButton(label: l.viewerShare, icon: AppIcons.share, onPressed: _share)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
