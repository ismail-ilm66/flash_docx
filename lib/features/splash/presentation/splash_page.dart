import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_colors.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';

/// Plays the 3 logo frames (~900 ms) while start-up work finishes, then
/// routes to Home. `flutter_native_splash` shows the static icon before this.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _frames = [
    'assets/splash/logo_frame_1.png',
    'assets/splash/logo_frame_2.png',
    'assets/splash/logo_frame_3.png',
  ];
  static const _frameDuration = Duration(milliseconds: 300);

  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    _timer = Timer.periodic(_frameDuration, (t) {
      if (_frame >= _frames.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _frame++);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    final minimum = Future<void>.delayed(_frameDuration * _frames.length);
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
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = AppColors.dark;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: Image.asset(
            _frames[_frame],
            key: ValueKey(_frame),
            width: 120,
            height: 120,
          ),
        ),
      ),
    );
  }
}
