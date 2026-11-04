enum Flavor { dev, prod }

/// Build flavor. Set once in `main_dev.dart` / `main_prod.dart` before
/// anything else runs.
abstract final class FlavorConfig {
  static Flavor _flavor = Flavor.dev;

  static Flavor get flavor => _flavor;
  static bool get isDev => _flavor == Flavor.dev;
  static bool get isProd => _flavor == Flavor.prod;

  static void set(Flavor flavor) => _flavor = flavor;
}
