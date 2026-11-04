import 'package:flash_dox/app/bootstrap.dart';
import 'package:flash_dox/app/flavor.dart';

/// Default entry point = dev. Use `main_prod.dart` for store builds:
/// `flutter build appbundle -t lib/main_prod.dart`.
void main() => bootstrap(Flavor.dev);
