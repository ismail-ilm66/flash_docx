import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter/material.dart';

/// Ink colours as shown on screen; the export uses the same values.
const inkBlackColor = Color(0xFF15171A);
const inkBlueColor = Color(0xFF1F3FAE);
const _inkOriginalSwatch = Color(0xFF6B7078);

Color? inkColor(InkColor ink) => switch (ink) {
      InkColor.black => inkBlackColor,
      InkColor.blue => inkBlueColor,
      InkColor.original => null,
    };

String inkLabel(BuildContext context, InkColor ink) => switch (ink) {
      InkColor.black => context.l10n.inkBlack,
      InkColor.blue => context.l10n.inkBlue,
      InkColor.original => context.l10n.inkOriginal,
    };

/// A transparent signature PNG in its ink (a straight recolour of the
/// opaque pixels, like the export), or as scanned for Original.
Widget inkedImage(Widget image, InkColor ink) {
  final color = inkColor(ink);
  if (color == null) return image;
  return ColorFiltered(colorFilter: ColorFilter.mode(color, BlendMode.srcIn), child: image);
}

/// The round swatch used in the ink pickers.
class InkSwatch extends StatelessWidget {
  const InkSwatch(this.ink, {super.key, this.size = 22});
  final InkColor ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: inkColor(ink) ?? _inkOriginalSwatch,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      );
}
