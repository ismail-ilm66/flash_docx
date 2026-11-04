import 'dart:async';

import 'package:flash_dox/app/app.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/flavor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

Future<void> bootstrap(Flavor flavor) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  FlavorConfig.set(flavor);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (flavor == Flavor.dev) {
    Bloc.observer = _LogObserver();
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // TODO(owner): forward to Crashlytics once Firebase config files exist.
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  await configureDependencies();

  runApp(const FlashDoxApp());
}

class _LogObserver extends BlocObserver {
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    debugPrint('${bloc.runtimeType} error: $error');
    super.onError(bloc, error, stackTrace);
  }
}
