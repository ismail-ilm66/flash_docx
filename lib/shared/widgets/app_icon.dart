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
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: c == null ? null : ColorFilter.mode(c, BlendMode.srcIn),
      );
    }
    return Icon(icon.fallback, size: size, color: c);
  }
}
