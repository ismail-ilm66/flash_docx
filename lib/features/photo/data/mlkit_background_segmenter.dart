import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/photo/domain/background_segmenter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:injectable/injectable.dart';

/// ML Kit selfie segmentation (Android and iOS). The model ships inside the
/// app, so it works offline and without Play services downloads. Runs on an
/// 800 px copy: the mask comes back over the platform channel as one number
/// per pixel.
@LazySingleton(as: BackgroundSegmenter)
class MlKitBackgroundSegmenter implements BackgroundSegmenter {
  MlKitBackgroundSegmenter(this._processor, this._files);

  final ImageProcessor _processor;
  final FileStore _files;

  /// false after a failure that means "not on this phone".
  bool _available = true;

  @override
  Future<String?> maskFor(String photoPath) async {
    if (!_available) return null;
    final id = newId();
    final small = _files.newCapturePath('seg_$id');
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);
    try {
      await _processor.render(
        photoPath,
        const PageEdits(filter: FilterType.original),
        size: RenderSize.mask,
        outputPath: small,
        jpegQuality: 90,
      );
      final mask = await segmenter.processImage(InputImage.fromFilePath(small));
      if (mask == null) return null;
      final bytes = Uint8List(mask.width * mask.height);
      final c = mask.confidences;
      for (var i = 0; i < bytes.length && i < c.length; i++) {
        bytes[i] = (c[i] * 255).round().clamp(0, 255);
      }
      final out = _files.newCapturePath('mask_$id').replaceAll('.jpg', '.png');
      await _processor.writeGrayImage(bytes, mask.width, mask.height, out);
      debugPrint('[background] mask ${mask.width}x${mask.height}');
      return out;
    } on MissingPluginException {
      _available = false;
      return null;
    } on Object catch (e) {
      debugPrint('[background] segmentation failed: $e');
      return null;
    } finally {
      await segmenter.close().catchError((_) {});
    }
  }
}
