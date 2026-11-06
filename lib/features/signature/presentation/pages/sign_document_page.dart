import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/signature/data/signature_store.dart';
import 'package:flash_dox/features/signature/presentation/widgets/ink.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// Opens Sign a document; the first time, My signature comes first.
Future<void> openSignFlow(BuildContext context, String documentId, {String? pageId}) async {
  if (!getIt<SignatureStore>().saved.value) {
    final made = await context.push<bool>(Routes.signature);
    if (made != true || !context.mounted) return;
  }
  await context.push(Routes.sign(documentId, pageId: pageId));
}

/// "05 Nov 2026".
String dateStampText(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

/// The date stamp as a transparent PNG in the app's font, so it's placed,
/// inked and exported exactly like a signature.
Future<Uint8List> renderDateStamp(String text) async {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 72, fontWeight: FontWeight.w600, color: Colors.black),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 8.0;
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(pad, pad));
  final img = await rec.endRecording().toImage((tp.width + pad * 2).ceil(), (tp.height + pad * 2).ceil());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  tp.dispose();
  return data!.buffer.asUint8List();
}

Future<Size> _pngSize(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// Sign a document (feature 4, artboard *Sign document*): place the saved
/// signature and date stamps on the pages. Overlays live in each page's
/// edits; Done saves them, the viewer re-renders, the export composites.
class SignDocumentPage extends StatefulWidget {
  const SignDocumentPage({required this.documentId, super.key, this.initialPageId});

  final String documentId;
  final String? initialPageId;

  @override
  State<SignDocumentPage> createState() => _SignDocumentPageState();
}

class _SignDocumentPageState extends State<SignDocumentPage> {
  final SignatureStore _store = getIt<SignatureStore>();
  final FileStore _files = getIt<FileStore>();

  ScanDocument? _doc;
  int _index = 0;

  /// Working copy of each page's overlays.
  final Map<String, List<PageOverlay>> _overlays = {};

  /// The page without overlays, and its aspect (width / height).
  final Map<String, String> _base = {};
  final Map<String, double> _aspect = {};

  String? _selected;
  late InkColor _ink = _store.defaultInk;
  bool _saving = false;

  /// Overlay files created on this screen; deleted again if not saved.
  final Set<String> _created = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final doc = (await getIt<GetDocument>()(widget.documentId)).toNullable();
    if (!mounted || doc == null) return;
    final pages = doc.sortedPages;
    setState(() {
      _doc = doc;
      _index = math.max(0, pages.indexWhere((p) => p.id == widget.initialPageId));
      for (final pg in pages) {
        _overlays[pg.id] = [...pg.edits.overlays];
      }
    });
    await _ensureBase(pages[_index]);
  }

  ScanPage? get _page => _doc?.sortedPages[_index];

  Future<void> _ensureBase(ScanPage page) async {
    if (_base.containsKey(page.id)) return;
    final out = _files.signBasePath(page.id, page.originalPath, page.edits);
    if (!File(out).existsSync()) {
      await getIt<ImageProcessor>().render(
        page.originalPath,
        page.edits.copyWith(overlays: const []),
        size: RenderSize.preview,
        outputPath: out,
        jpegQuality: 85,
        priority: JobPriority.interactive,
      );
    }
    final size = await _pngSize(out);
    if (!mounted) return;
    setState(() {
      _base[page.id] = out;
      _aspect[page.id] = size.width / size.height;
    });
  }

  void _goTo(int i) {
    final pages = _doc!.sortedPages;
    if (i < 0 || i >= pages.length) return;
    setState(() {
      _index = i;
      _selected = null;
    });
    unawaited(_ensureBase(pages[i]));
  }

  bool get _changed {
    for (final pg in _doc?.pages ?? const <ScanPage>[]) {
      final now = _overlays[pg.id] ?? const [];
      if (now.length != pg.edits.overlays.length) return true;
      for (var i = 0; i < now.length; i++) {
        if (now[i] != pg.edits.overlays[i]) return true;
      }
    }
    return false;
  }

  void _update(PageOverlay o) {
    final page = _page!;
    setState(() => _overlays[page.id] = [for (final x in _overlays[page.id]!) x.id == o.id ? o : x]);
  }

  void _remove(String id) {
    final page = _page!;
    setState(() {
      _overlays[page.id] = [..._overlays[page.id]!.where((x) => x.id != id)];
      if (_selected == id) _selected = null;
    });
  }

  /// Adds an overlay [widthFraction] of the page wide, keeping the PNG's
  /// shape, at ([left], [bottom]) in page fractions.
  Future<void> _add(OverlayKind kind, String path, {required double widthFraction, required double left, required double bottom}) async {
    final page = _page!;
    final aspect = _aspect[page.id] ?? 0.707;
    final png = await _pngSize(path);
    final w = widthFraction;
    final h = (w * aspect) * png.height / png.width;
    final o = PageOverlay(
      id: newId(),
      kind: kind,
      imagePath: path,
      left: left.clamp(0, 1 - w),
      top: (1 - bottom - h).clamp(0, math.max(0, 1 - h)),
      width: w,
      height: math.min(h, 1),
      ink: kind == OverlayKind.date && _ink == InkColor.original ? InkColor.black : _ink,
    );
    _created.add(path);
    if (!mounted) return;
    setState(() {
      _overlays[page.id] = [..._overlays[page.id]!, o];
      _selected = o.id;
    });
  }

  Future<void> _addSignature() async {
    if (!_store.saved.value) {
      final made = await context.push<bool>(Routes.signature);
      if (made != true || !mounted) return;
      setState(() => _ink = _store.defaultInk);
    }
    final path = await _store.adoptInto(widget.documentId);
    await _add(OverlayKind.signature, path, widthFraction: 0.38, left: 0.08, bottom: 0.1);
  }

  Future<void> _addDate() async {
    final png = await renderDateStamp(dateStampText(DateTime.now()));
    final path = await _store.adoptInto(widget.documentId, png: png);
    await _add(OverlayKind.date, path, widthFraction: 0.28, left: 0.6, bottom: 0.11);
  }

  void _setInk(InkColor ink) {
    setState(() => _ink = ink);
    final sel = _overlays[_page?.id]?.where((o) => o.id == _selected).firstOrNull;
    if (sel != null && !(sel.kind == OverlayKind.date && ink == InkColor.original)) _update(sel.copyWith(ink: ink));
  }

  Future<void> _done() async {
    final doc = _doc!;
    if (!_changed) {
      await _cleanUp(keep: {for (final pg in doc.pages) ...pg.edits.overlays.map((o) => o.imagePath)});
      if (mounted) context.pop();
      return;
    }
    setState(() => _saving = true);
    final changed = [
      for (final pg in doc.pages)
        if (_overlays[pg.id]!.length != pg.edits.overlays.length || !_sameOverlays(_overlays[pg.id]!, pg.edits.overlays))
          // A new preview and thumbnail render with the overlays; the text
          // doesn't change.
          pg.copyWith(edits: pg.edits.copyWith(overlays: _overlays[pg.id]!), processedPath: null, thumbPath: null),
    ];
    final r = await getIt<UpdatePages>()(changed);
    if (!mounted) return;
    if (r.isLeft()) {
      setState(() => _saving = false);
      context.showSnack(context.l10n.errorGeneric, error: true);
      return;
    }
    await getIt<LogActivity>()(doc.id, ActivityType.signed);
    await _cleanUp(keep: {for (final list in _overlays.values) ...list.map((o) => o.imagePath)});
    if (mounted) context.pop();
  }

  static bool _sameOverlays(List<PageOverlay> a, List<PageOverlay> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Deletes overlay files nothing points to any more.
  Future<void> _cleanUp({required Set<String> keep}) async {
    final dir = Directory(p.join(_files.docDir(widget.documentId).path, 'overlays'));
    if (!dir.existsSync()) return;
    await for (final f in dir.list()) {
      if (f is File && !keep.contains(f.path)) await f.delete();
    }
  }

  Future<void> _cancel() async {
    final doc = _doc;
    if (doc != null) {
      await _cleanUp(keep: {for (final pg in doc.pages) ...pg.edits.overlays.map((o) => o.imagePath)});
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final doc = _doc;
    final page = _page;
    final pages = doc?.sortedPages ?? const <ScanPage>[];
    final base = page == null ? null : _base[page.id];
    final overlays = page == null ? const <PageOverlay>[] : _overlays[page.id]!;
    final selected = overlays.where((o) => o.id == _selected).firstOrNull;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) unawaited(_cancel());
      },
      child: AppScaffold(
        topBar: AppTopBar(
          leading: TopBarLeading.close,
          onLeading: _saving ? null : _cancel,
          title: l.signTitle,
          subtitle: pages.length > 1 ? l.pageOfTotal(_index + 1, pages.length) : null,
          actions: [TopBarTextAction(label: l.enhanceDone, onPressed: doc == null || _saving ? null : _done)],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: c.stage,
                    child: Column(
                      children: [
                        Expanded(
                          child: base == null
                              ? const Center(child: CircularProgressIndicator())
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(Space.x6, Space.x5, Space.x6, Space.x3),
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: _aspect[page!.id]!,
                                      child: _PageWithOverlays(
                                        image: base,
                                        overlays: overlays,
                                        selected: _selected,
                                        onSelect: (id) => setState(() => _selected = id),
                                        onChanged: _update,
                                        onRemove: _remove,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.x3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (pages.length > 1)
                                IconButton(
                                  tooltip: l.signPrevPage,
                                  onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                                  icon: AppIcon(AppIcons.back, size: 18, color: c.text),
                                ),
                              Flexible(
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 30),
                                  padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 4),
                                  decoration: BoxDecoration(color: c.chip, borderRadius: Radii.pillR),
                                  child: Center(
                                    widthFactor: 1,
                                    child: FitText(
                                      l.signHint,
                                      style: context.text.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ),
                              if (pages.length > 1)
                                IconButton(
                                  tooltip: l.signNextPage,
                                  onPressed: _index < pages.length - 1 ? () => _goTo(_index + 1) : null,
                                  icon: Transform.flip(flipX: true, child: AppIcon(AppIcons.back, size: 18, color: c.text)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                l.signInk.toUpperCase(),
                                style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                              ),
                              const SizedBox(width: 10),
                              for (final ink in [
                                InkColor.black,
                                InkColor.blue,
                                if (selected?.kind == OverlayKind.signature) InkColor.original,
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: Space.x2),
                                  child: Semantics(
                                    button: true,
                                    selected: (selected?.ink ?? _ink) == ink,
                                    label: inkLabel(context, ink),
                                    child: InkResponse(
                                      onTap: () => _setInk(ink),
                                      radius: 22,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: (selected?.ink ?? _ink) == ink ? c.accent : c.border,
                                            width: (selected?.ink ?? _ink) == ink ? 2 : 1,
                                          ),
                                        ),
                                        child: InkSwatch(ink),
                                      ),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Flexible(
                                flex: 4,
                                child: TextButton(
                                  onPressed: () async {
                                    final made = await context.push<bool>(Routes.signature);
                                    if ((made ?? false) && mounted) setState(() => _ink = _store.defaultInk);
                                  },
                                  child: FitText(l.signChange, maxLines: 1),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.x3),
                          Row(
                            children: [
                              Expanded(
                                child: SecondaryButton(
                                  label: l.signAddDate,
                                  icon: AppIcons.clock,
                                  dense: true,
                                  onPressed: base == null ? null : _addDate,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PrimaryButton(
                                  label: l.signAddSignature,
                                  icon: AppIcons.signature,
                                  dense: true,
                                  onPressed: base == null ? null : _addSignature,
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
            if (_saving) ProgressOverlay(label: l.sharePreparing),
          ],
        ),
      ),
    );
  }
}

/// The page with its overlays as movable boxes. Tapping the page clears the
/// selection.
class _PageWithOverlays extends StatelessWidget {
  const _PageWithOverlays({
    required this.image,
    required this.overlays,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onRemove,
  });

  final String image;
  final List<PageOverlay> overlays;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<PageOverlay> onChanged;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => onSelect(null),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 6))],
                  ),
                  child: Image.file(File(image), fit: BoxFit.fill, gaplessPlayback: true),
                ),
              ),
            ),
            for (final o in overlays)
              OverlayBox(
                key: ValueKey(o.id),
                overlay: o,
                page: size,
                selected: o.id == selected,
                onSelect: () => onSelect(o.id),
                onChanged: onChanged,
                onRemove: () => onRemove(o.id),
              ),
          ],
        );
      },
    );
  }
}

/// A placed signature or date: drag to move, the corner handle to resize
/// (shape kept), ✕ to remove. Positions are page fractions.
class OverlayBox extends StatelessWidget {
  const OverlayBox({
    required this.overlay,
    required this.page,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final PageOverlay overlay;
  final Size page;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<PageOverlay> onChanged;
  final VoidCallback onRemove;

  /// Room around the box for the ✕ and the handle, so they stay tappable.
  static const _m = 14.0;
  static const _minPx = 36.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final o = overlay;
    final w = o.width * page.width;
    final h = o.height * page.height;

    void move(Offset d) {
      onChanged(o.copyWith(
        left: (o.left + d.dx / page.width).clamp(0, math.max(0, 1 - o.width)),
        top: (o.top + d.dy / page.height).clamp(0, math.max(0, 1 - o.height)),
      ));
    }

    void resize(Offset d) {
      final ratio = h / w;
      final maxW = math.min((1 - o.left) * page.width, (1 - o.top) * page.height / ratio);
      final nw = (w + d.dx).clamp(math.min(_minPx, maxW), maxW);
      onChanged(o.copyWith(width: nw / page.width, height: nw * ratio / page.height));
    }

    return Positioned(
      left: o.left * page.width - _m,
      top: o.top * page.height - _m,
      width: w + _m * 2,
      height: h + _m * 2,
      child: Stack(
        children: [
          Positioned.fill(
            left: _m,
            top: _m,
            right: _m,
            bottom: _m,
            child: GestureDetector(
              onTap: onSelect,
              onPanStart: (_) => onSelect(),
              onPanUpdate: (d) => move(d.delta),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: selected ? Border.all(color: c.accent, width: 2) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: inkedImage(Image.file(File(o.imagePath), fit: BoxFit.contain, gaplessPlayback: true), o.ink),
                ),
              ),
            ),
          ),
          if (selected) ...[
            Positioned(
              left: 0,
              top: 0,
              child: Semantics(
                button: true,
                label: l.signRemove,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.accent, width: 2),
                    ),
                    child: AppIcon(AppIcons.close, size: 14, color: c.text),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (d) => resize(d.delta),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
