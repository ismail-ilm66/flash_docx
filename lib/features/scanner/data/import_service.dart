import 'package:file_picker/file_picker.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:injectable/injectable.dart';

/// Gallery (system photo picker, no permission) and Files app import.
@lazySingleton
class ImportService {
  ImportService(this._picker);

  final ImagePicker _picker;

  Future<Either<Failure, List<String>>> fromGallery({bool multiple = true}) async {
    try {
      if (multiple) {
        final files = await _picker.pickMultiImage(limit: 50);
        if (files.isEmpty) return const Left(CancelledFailure());
        return Right(files.map((f) => f.path).toList());
      }
      final f = await _picker.pickImage(source: ImageSource.gallery);
      if (f == null) return const Left(CancelledFailure());
      return Right([f.path]);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  /// Round 11 (Reduce size): one PDF from the Files app (a copy; no
  /// storage permission).
  Future<Either<Failure, String>> pdfFromFiles() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = files.map((f) => f.path).whereType<String>().firstOrNull;
      if (path == null) return const Left(CancelledFailure());
      return Right(path);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  Future<Either<Failure, List<String>>> fromFiles() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      final paths = files.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return const Left(CancelledFailure());
      return Right(paths);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
