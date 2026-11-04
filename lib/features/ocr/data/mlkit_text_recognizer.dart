import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart' as domain;
import 'package:fpdart/fpdart.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' as ml;
import 'package:injectable/injectable.dart';

/// On-device ML Kit, Latin script only (no Urdu).
@LazySingleton(as: domain.TextRecognizer)
class MlKitTextRecognizer implements domain.TextRecognizer {
  ml.TextRecognizer? _recognizer;

  ml.TextRecognizer get _r =>
      _recognizer ??= ml.TextRecognizer(script: ml.TextRecognitionScript.latin);

  @override
  Future<Either<Failure, String>> read(String imagePath) async {
    try {
      final result = await _r.processImage(ml.InputImage.fromFilePath(imagePath));
      // Rebuild with block/line structure so paragraphs survive.
      final buf = StringBuffer();
      for (final block in result.blocks) {
        for (final line in block.lines) {
          buf.writeln(line.text);
        }
        buf.writeln();
      }
      return Right(buf.toString().trim());
    } catch (e) {
      return Left(OcrFailure(e.toString()));
    }
  }

  @override
  @disposeMethod
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
