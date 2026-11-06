import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Base scaffold. The always-dark screens (Camera, Adjust edges, Enhance) get
/// their theme from the router.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    super.key,
    this.topBar,
    this.bottomBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final PreferredSizeWidget? topBar;
  final Widget? bottomBar;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return Builder(
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
  }
}
