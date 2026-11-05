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
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

/// The Flutter half of a single splash (round 3, P1-1).
///
/// Its first frame is identical to the native splash: the same 1152 px mark
/// at 288 dp, dead centre on #0F1012. The native splash is only removed once
/// that image is decoded, so there's no blank frame in between. Then the
/// wordmark fades in below the mark; the mark itself never moves.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  /// Same file and size as `flutter_native_splash` (pubspec.yaml).
  static const markAsset = 'assets/splash/splash_mark_1152.png';
  static const double markSize = 288;

  /// The glyph fills the middle 432 of the 1152 px canvas vertically.
  static const double glyphHalfHeight = markSize * 432 / 1152 / 2;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  static const _hold = Duration(milliseconds: 900);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_handOver());
    unawaited(_start());
  }

  /// Decode the mark first, then drop the native splash: the swap is
  /// invisible because both show the same pixels.
  Future<void> _handOver() async {
    try {
      await precacheImage(const AssetImage(SplashPage.markAsset), context);
    } catch (_) {}
    FlutterNativeSplash.remove();
    if (mounted) unawaited(_intro.forward());
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
    final words = still ? const AlwaysStoppedAnimation<double>(1) : CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Exactly where the native splash draws it: full-screen centre,
          // no SafeArea, no scaling, no animation.
          const Center(
            child: Image(
              image: AssetImage(SplashPage.markAsset),
              width: SplashPage.markSize,
              height: SplashPage.markSize,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          ),
          // Wordmark below the glyph, fading in.
          Align(
            child: Transform.translate(
              offset: const Offset(0, SplashPage.glyphHalfHeight + Space.x8 + 30),
              child: FadeTransition(
                opacity: words,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.appName.toUpperCase(),
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 30,
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
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.x12),
                child: FadeTransition(
                  opacity: words,
                  child: Text(
                    AppInfo.publisher,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
