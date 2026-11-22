import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/constants/app_info.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/scanner/data/camera_list.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

/// The Flutter half of a single splash (round 3, P1-1).
///
/// Its first frame is identical to the native splash: the same 1152 px mark
/// at 288 dp, dead centre on the theme's `bg`. Colours follow the theme the
/// user picked; the native splash follows the system (and, on Android 12+,
/// the picked theme too: see `ThemeCubit`). The native splash is only removed once
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

  /// Round 6, P0-4: on a low-RAM phone, decoded images are capped too, so
  /// only the pages on screen stay in memory at full size.
  Future<void> _loadDeviceProfile() async {
    final device = getIt<DeviceProfile>();
    await device.load();
    if (device.isLowRam) {
      PaintingBinding.instance.imageCache
        ..maximumSizeBytes = 40 << 20
        ..maximumSize = 50;
    }
  }

  /// Temp files from the last run go; so do the documents' cached page
  /// images when pages now render differently ([FileStore.renderVersion]).
  Future<void> _refreshPageCaches(FileStore files) async {
    final prefs = getIt<PrefsService>();
    if (prefs.renderVersion >= FileStore.renderVersion) return files.clearExportTemp();
    await files.clearCaches();
    await prefs.setRenderVersion(FileStore.renderVersion);
  }

  Future<void> _start() async {
    // Round 10, P0-2: the camera list is ready before the first scan.
    CameraList.preload();
    final minimum = Future<void>.delayed(_hold);
    // Housekeeping (round 6, P0-3): export and capture temp files from the
    // previous run. Export page renders live with their documents now.
    final files = getIt<FileStore>();
    // Round 7, P0-3: an unsaved scan from the last run, for Home's card.
    final work = Future.wait<void>([
      _refreshPageCaches(files),
      _loadDeviceProfile(),
      getIt<DraftService>().init(),
    ]).catchError((_) => const <void>[]);
    await Future.wait([minimum, work]);
    if (!mounted) return;
    context.go(Routes.home);
    // Round 10, P0-3: display images missing from older documents are made
    // in the background, once Home has settled.
    Future<void>.delayed(const Duration(seconds: 3), () => getIt<PageRenderService>().ensureAllCaches()).catchError((Object e) {
      debugPrint('[cache] $e');
    }).ignore();
    // Ads SDK + consent when rewarded ads are on (a no-op in v1); never
    // blocks start-up.
    unawaited(getIt<RewardGate>().initialize());
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
