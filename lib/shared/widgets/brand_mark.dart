import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Flash Dox logo mark (round 11, option C: scan corners around a page
/// with a bolt), `flashdox_mark_amber.svg`, square, in its own colours.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.width = 32});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/flashdox_mark_amber.svg',
      width: width,
      height: width,
      excludeFromSemantics: true,
    );
  }
}
