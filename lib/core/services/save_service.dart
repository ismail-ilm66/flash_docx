import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:gal/gal.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Saves exports to the phone: images go to Photos/Gallery via `gal`, PDFs go
/// through the system save dialog. Neither needs a storage permission.
@lazySingleton
class SaveService {
  Future<Either<Failure, Unit>> saveImages(List<File> files) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final ok = await Gal.requestAccess(toAlbum: true);
        if (!ok) return const Left(PermissionFailure());
      }
      for (final f in files) {
        await Gal.putImage(f.path, album: 'Flash Dox');
      }
      return const Right(unit);
    } on GalException catch (e) {
      return Left(
        e.type == GalExceptionType.accessDenied
            ? const PermissionFailure()
            : StorageFailure(e.type.message),
      );
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  /// Opens the OS "save to" dialog. Returns `CancelledFailure` when dismissed.
  Future<Either<Failure, String>> saveFileWithDialog(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final name = p.basename(file.path);
      final ext = p.extension(name).replaceFirst('.', '');
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(bytes),
        mimeType: ext == 'pdf' ? 'application/pdf' : 'application/octet-stream',
      );
      if (uri == null) return const Left(CancelledFailure());
      // file_picker writes `bytes` itself on mobile; nothing else to do.
      return Right(uri.toString());
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }
}
