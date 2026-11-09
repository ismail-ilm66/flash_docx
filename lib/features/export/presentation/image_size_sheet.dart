import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PixelSize = ({int width, int height});

/// Passport photo pixel sizes for online forms: the print size at 300 DPI,
/// then common widths, all in the photo's own shape.
List<PixelSize> pixelSizePresets(double widthMm, double heightMm) {
  int px(double mm) => (mm / 25.4 * 300).round();
  final aspect = widthMm / heightMm;
  return [
    (width: px(widthMm), height: px(heightMm)),
    for (final w in const [600, 900, 1200])
      (width: w, height: (w / aspect).round()),
  ];
}

String imageSizeLabel(BuildContext context, PixelSize? size) => size == null
    ? context.l10n.imageSizeFull
    : context.l10n.imageSizePx(size.width, size.height);

/// Image size (passport photo Share): full resolution, the presets, or a
/// custom width × height. Returns `size: null` for full resolution, or null
/// when dismissed.
Future<({PixelSize? size})?> showImageSizeSheet(
  BuildContext context, {
  required PixelSize? current,
  required double widthMm,
  required double heightMm,
}) {
  final l = context.l10n;
  final presets = pixelSizePresets(widthMm, heightMm);
  return AppBottomSheet.show<({PixelSize? size})>(
    context,
    builder: (ctx) => AppBottomSheet(
      title: l.shareImageSize,
      padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x4),
      child: Column(
        children: [
          SheetAction(
            label: l.imageSizeFull,
            selected: current == null,
            onTap: () => Navigator.of(ctx).pop((size: null)),
          ),
          for (final (i, s) in presets.indexed)
            SheetAction(
              label: i == 0
                  ? l.imageSizePrint(s.width, s.height)
                  : l.imageSizePx(s.width, s.height),
              selected: current == s,
              onTap: () => Navigator.of(ctx).pop((size: s)),
            ),
          SheetAction(
            label: current != null && !presets.contains(current)
                ? '${l.imageSizeCustom} · ${l.imageSizePx(current.width, current.height)}'
                : l.imageSizeCustom,
            selected: current != null && !presets.contains(current),
            onTap: () async {
              final custom = await _customSize(ctx, current ?? presets[1]);
              if (custom != null && ctx.mounted) {
                Navigator.of(ctx).pop((size: custom));
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<PixelSize?> _customSize(BuildContext context, PixelSize start) async {
  final l = context.l10n;
  final w = TextEditingController(text: '${start.width}');
  final h = TextEditingController(text: '${start.height}');
  final picked = await showDialog<PixelSize>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.imageSizeCustom),
      content: Row(
        children: [
          for (final (c, label) in [
            (w, l.imageSizeWidth),
            (h, l.imageSizeHeight),
          ]) ...[
            if (c == h) const SizedBox(width: Space.x3),
            Expanded(
              child: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
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
            final pw = int.tryParse(w.text);
            final ph = int.tryParse(h.text);
            if (pw == null ||
                ph == null ||
                pw < 100 ||
                ph < 100 ||
                pw > 4000 ||
                ph > 4000) {
              return;
            }
            Navigator.of(ctx).pop((width: pw, height: ph));
          },
          child: Text(l.commonDone),
        ),
      ],
    ),
  );
  w.dispose();
  h.dispose();
  return picked;
}
