import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Flash Dox logo mark (P1-1): `flash_dox_logo_mark.svg`, whose viewBox
/// is trimmed to the glyph (39 × 32), drawn in its own colours and centred
/// in its box so it never sits off to one side.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.width = 34});

  final double width;

  static const double _aspect = 39 / 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width / _aspect,
      child: Center(
        child: SvgPicture.asset(
          'assets/images/logo_mark.svg',
          width: width,
          height: width / _aspect,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
