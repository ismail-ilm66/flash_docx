import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Flash Dox flashlight mark (40 × 24 artwork).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.width = 34, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/brand_mark.svg',
      width: width,
      height: width * 24 / 40,
      colorFilter: ColorFilter.mode(color ?? context.colors.accent, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
