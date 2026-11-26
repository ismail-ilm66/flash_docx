import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/photo/domain/face_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:injectable/injectable.dart';

/// ML Kit face detection (bundled model: offline, no Play services
/// download), on the same 800 px upright copy the person mask uses.
@LazySingleton(as: FaceLocator)
class MlKitFaceLocator implements FaceLocator {
  MlKitFaceLocator(this._processor, this._files);

  final ImageProcessor _processor;
  final FileStore _files;

  /// false after a failure that means "not on this phone".
  bool _available = true;

  @override
  Future<List<double>?> faceBox(String photoPath) async {
    if (!_available) return null;
    final small = _files.newCapturePath('face_${newId()}');
    final detector = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.15));
    try {
      await _processor.render(
        photoPath,
        const PageEdits(filter: FilterType.original),
        size: RenderSize.mask,
        outputPath: small,
        jpegQuality: 90,
      );
      final size = await _processor.imageSize(small);
      final faces = await detector.processImage(InputImage.fromFilePath(small));
      if (faces.isEmpty) return null;
      final face = faces.reduce((a, b) => a.boundingBox.width * a.boundingBox.height >= b.boundingBox.width * b.boundingBox.height ? a : b);
      final r = face.boundingBox;
      final (w, h) = (size.width.toDouble(), size.height.toDouble());
      debugPrint('[face] ${r.width.round()}×${r.height.round()} in ${size.width}×${size.height}');
      return [
        (r.left / w).clamp(0.0, 1.0),
        (r.top / h).clamp(0.0, 1.0),
        (r.right / w).clamp(0.0, 1.0),
        (r.bottom / h).clamp(0.0, 1.0),
      ];
    } on MissingPluginException {
      _available = false;
      return null;
    } on Object catch (e) {
      debugPrint('[face] detection failed: $e');
      return null;
    } finally {
      await detector.close().catchError((_) {});
    }
  }
}
