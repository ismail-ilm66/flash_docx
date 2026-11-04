import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class TextRecognizer {
  /// Reads Latin-script text from an image on the device.
  Future<Either<Failure, String>> read(String imagePath);
  Future<void> dispose();
}
