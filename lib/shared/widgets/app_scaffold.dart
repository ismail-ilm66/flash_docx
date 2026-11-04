import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Base scaffold. `forceDark` wraps the screen in the dark theme regardless
/// of the user's setting (Camera, Adjust edges, Enhance).
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    super.key,
    this.topBar,
    this.bottomBar,
    this.forceDark = false,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final PreferredSizeWidget? topBar;
  final Widget? bottomBar;
  final bool forceDark;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    Widget child = Builder(
      builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: backgroundColor ?? context.colors.bg,
          appBar: topBar,
          body: body,
          bottomNavigationBar: bottomBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
        ),
      ),
    );
    if (forceDark) child = Theme(data: AppTheme.dark, child: child);
    return child;
  }
}
