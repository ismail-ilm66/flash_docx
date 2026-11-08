import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/signature/data/signature_store.dart';
import 'package:flash_dox/features/signature/presentation/widgets/draw_pad.dart';
import 'package:flash_dox/features/signature/presentation/widgets/ink.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum _Source { scan, draw }

/// My signature (feature 4, artboard *My signature*): scan it from paper or
/// draw it, pick the ink, save. Pops `true` once saved.
class MySignaturePage extends StatefulWidget {
  const MySignaturePage({super.key});

  @override
  State<MySignaturePage> createState() => _MySignaturePageState();
}

class _MySignaturePageState extends State<MySignaturePage> {
  final SignatureStore _store = getIt<SignatureStore>();
  final _pad = DrawPadController();
  _Source _source = _Source.scan;
  late InkColor _ink = _store.defaultInk;
  String? _scanned;
  bool _busy = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final shot = await context.push<RetakeShot>(Routes.camera, extra: const CameraArgs(retake: true, mode: ScanMode.document, hint: CameraHint.signature));
    if (shot == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = getIt<FileStore>().newCapturePath('signature_${newId()}').replaceAll('.jpg', '.png');
      await getIt<ImageProcessor>().signatureFromPhoto(shot.path, outputPath: out, capture: shot.capture);
      if (mounted) setState(() => _scanned = out);
    } on Object {
      if (mounted) context.showSnack(context.l10n.mySignatureNotFound, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canSave => _source == _Source.scan ? _scanned != null : !_pad.isEmpty;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final Uint8List bytes;
      if (_source == _Source.scan) {
        bytes = await File(_scanned!).readAsBytes();
      } else {
        final img = await _pad.toImage();
        final data = await img!.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        bytes = data!.buffer.asUint8List();
      }
      // A drawn signature has no "original" colour: black is the same.
      await _store.save(bytes, ink: _source == _Source.draw && _ink == InkColor.original ? InkColor.black : _ink);
      if (mounted) context.pop(true);
    } on Object {
      if (mounted) context.showSnack(context.l10n.errorGeneric, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final inks = [InkColor.black, InkColor.blue, if (_source == _Source.scan) InkColor.original];
    return AppScaffold(
      topBar: AppTopBar(title: l.mySignatureTitle),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.x5, Space.x1, Space.x5, Space.x4),
                  children: [
                    SegmentedPills<_Source>(
                      values: _Source.values,
                      selected: _source,
                      height: 42,
                      labelOf: (v) => v == _Source.scan ? l.mySignatureScan : l.mySignatureDraw,
                      onChanged: (v) => setState(() {
                        _source = v;
                        if (v == _Source.draw && _ink == InkColor.original) _ink = InkColor.black;
                      }),
                    ),
                    const SizedBox(height: Space.x4),
                    SizedBox(
                      height: 230,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: c.border),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: CustomPaint(
                            painter: _Checkerboard(c.isDark),
                            child: _source == _Source.draw ? _drawArea(context) : _scanArea(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.x4),
                    SectionLabel(l.mySignatureInk, padding: const EdgeInsets.only(bottom: Space.x2)),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final ink in inks)
                          _InkChip(ink: ink, selected: _ink == ink, onTap: () => setState(() => _ink = ink)),
                      ],
                    ),
                    const SizedBox(height: Space.x4),
                    Container(
                      padding: const EdgeInsets.all(Space.x3),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppIcon(AppIcons.info, size: 18, color: c.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _source == _Source.scan ? l.mySignatureScanTip : l.mySignatureDrawTip,
                              style: context.text.bodySmall?.copyWith(height: 1.5, color: c.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x5, Space.x3, Space.x5, Space.x5),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: _source == _Source.scan ? l.mySignatureRetake : l.mySignatureClear,
                          onPressed: _busy
                              ? null
                              : _source == _Source.scan
                              ? (_scanned == null ? null : _takePhoto)
                              : (_pad.isEmpty ? null : _pad.clear),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _pad,
                          builder: (context, _) => PrimaryButton(
                            label: l.mySignatureSave,
                            loading: _busy,
                            onPressed: _canSave ? _save : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scanArea(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    if (_scanned == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            : PrimaryButton(label: l.mySignatureTakePhoto, icon: AppIcons.camera, expand: false, onPressed: _takePhoto),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(Space.x6),
            child: inkedImage(Image.file(File(_scanned!), fit: BoxFit.contain, gaplessPlayback: true), _ink),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xBF0F1012), borderRadius: BorderRadius.circular(13)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.check, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(l.mySignatureBgRemoved, style: context.text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        if (_busy) ColoredBox(color: c.scrim, child: const Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _drawArea(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Stack(
      children: [
        Positioned(
          left: Space.x6,
          right: Space.x6,
          bottom: 56,
          child: Container(height: 1, color: c.borderStrong),
        ),
        Positioned.fill(child: DrawPad(controller: _pad, ink: inkColor(_ink) ?? inkBlackColor)),
        Positioned(
          right: Space.x1,
          top: Space.x1,
          child: ListenableBuilder(
            listenable: _pad,
            builder: (context, _) => TextButton(
              onPressed: _pad.isEmpty ? null : _pad.undo,
              child: Text(l.mySignatureUndo),
            ),
          ),
        ),
      ],
    );
  }
}

class _InkChip extends StatelessWidget {
  const _InkChip({required this.ink, required this.selected, required this.onTap});
  final InkColor ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.accent : c.border, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkSwatch(ink),
                const SizedBox(width: Space.x2),
                Text(inkLabel(context, ink), style: context.text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Light checkerboard behind a transparent signature.
class _Checkerboard extends CustomPainter {
  _Checkerboard(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final a = Paint()..color = dark ? const Color(0xFFE6E6E2) : const Color(0xFFF7F7F5);
    final b = Paint()..color = dark ? const Color(0xFFD9D9D4) : const Color(0xFFECECE8);
    canvas.drawRect(Offset.zero & size, a);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = (y.isOdd ? 1 : 0); x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), b);
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard old) => old.dark != dark;
}
