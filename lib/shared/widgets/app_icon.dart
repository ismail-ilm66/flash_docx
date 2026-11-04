import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = Sizes.icon, this.color});

  final AppIcons icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color;
    final asset = icon.asset;
    if (asset != null) {
      // Same box model as Material's Icon: a size×size box with the glyph
      // centred, so a tight parent never stretches the artwork.
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: size,
            height: size,
            excludeFromSemantics: true,
            colorFilter: c == null ? null : ColorFilter.mode(c, BlendMode.srcIn),
          ),
        ),
      );
    }
    return Icon(icon.fallback, size: size, color: c);
  }
}
