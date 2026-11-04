import 'dart:io';

import 'package:flash_dox/app/flavor.dart';

/// AdMob unit IDs. Dev builds always use Google's public test units.
abstract final class AdIds {
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  // TODO(owner): production rewarded unit IDs.
  static const _prodRewardedAndroid = 'ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN';
  static const _prodRewardedIos = 'ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN';

  static String get rewarded {
    final test = FlavorConfig.isDev || _prodRewardedAndroid.contains('X');
    if (Platform.isIOS) return test ? _testRewardedIos : _prodRewardedIos;
    return test ? _testRewardedAndroid : _prodRewardedAndroid;
  }
}
