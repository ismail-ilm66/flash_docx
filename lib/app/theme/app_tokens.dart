import 'package:flutter/widgets.dart';

/// Spacing on a 4-point scale.
abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: x4);
}

abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;

  static final BorderRadius smR = BorderRadius.circular(sm);
  static final BorderRadius mdR = BorderRadius.circular(md);
  static final BorderRadius lgR = BorderRadius.circular(lg);
  static final BorderRadius xlR = BorderRadius.circular(xl);
  static final BorderRadius xxlR = BorderRadius.circular(xxl);
  static final BorderRadius pillR = BorderRadius.circular(pill);
}

abstract final class Sizes {
  /// Minimum tap target.
  static const double tap = 44;
  static const double fab = 64;
  static const double navBar = 76;
  static const double topBar = 68;
  static const double icon = 24;
  static const double iconSm = 20;
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
}
