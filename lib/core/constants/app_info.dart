abstract final class AppInfo {
  static const String name = 'Flash Dox';

  /// Publisher wordmark shown on the splash and in Settings.
  static const String publisher = 'SWTNOA';
  static const String androidPackage = 'com.swtnoa.flashdox';
  static const String iosBundleId = 'com.swtnoa.flashdox';

  /// GitHub Pages, from `site/` in this repo (see site/README.md).
  static const String siteUrl = 'https://ismail-ilm66.github.io/flash-dox-site';
  static const String privacyPolicyUrl = '$siteUrl/privacy.html';
  static const String faqUrl = '$siteUrl/faq.html';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackage';
  static const String appStoreUrl = 'https://apps.apple.com/app/id0000000000';
}
