import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_colors.dart';
import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/constants/app_info.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

/// Brand splash: the flashlight mark in its tile, the wordmark and tagline,
/// and the publisher name at the foot. Holds for ~900 ms while start-up work
/// finishes, then routes to Home. `flutter_native_splash` shows the static
/// icon before this.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  static const _hold = Duration(milliseconds: 900);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    unawaited(_intro.forward());
    unawaited(_start());
  }

  Future<void> _start() async {
    final minimum = Future<void>.delayed(_hold);
    // Housekeeping: export temp files from the previous run.
    final work = getIt<FileStore>().clearExportTemp().catchError((_) {});
    await Future.wait([minimum, work]);
    if (!mounted) return;
    context.go(Routes.home);
    // Consent form (EEA/UK) + ads SDK, shown over Home; never blocks start-up.
    unawaited(getIt<RewardGate>().initialize());
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = AppColors.dark;
    final l = context.l10n;
    final still = MediaQuery.disableAnimationsOf(context);
    final mark = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.8, curve: Curves.easeOutCubic));
    final words = CurvedAnimation(parent: _intro, curve: const Interval(0.25, 1, curve: Curves.easeOutCubic));
    Widget fadeUp(Animation<double> a, Widget child) => still
        ? child
        : FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
              child: child,
            ),
          );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 5),
            fadeUp(
              mark,
              ScaleTransition(
                scale: still ? const AlwaysStoppedAnimation(1) : Tween(begin: 0.92, end: 1.0).animate(mark),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: Radii.xxlR,
                    border: Border.all(color: c.border),
                  ),
                  alignment: Alignment.center,
                  child: BrandMark(width: 64, color: c.accent),
                ),
              ),
            ),
            const SizedBox(height: Space.x5),
            fadeUp(
              words,
              Column(
                children: [
                  Text(
                    l.appName.toUpperCase(),
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    l.splashTagline,
                    style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: c.muted),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 6),
            Text(
              AppInfo.publisher,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: c.muted,
              ),
            ),
            const SizedBox(height: Space.x12),
          ],
        ),
      ),
    );
  }
}
