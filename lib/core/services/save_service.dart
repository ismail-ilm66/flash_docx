import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:gal/gal.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Where the last "Save to phone" went: the folder shown to the user and
/// the file's uri (for Open).
typedef SavedTo = ({String folder, String uri, String mime});

/// Saves exports to the phone.
///
/// Round 11b, I3: on Android everything goes through the app's own save
/// channel: MediaStore into Pictures/Flash Dox (images) or Download/Flash
/// Dox (PDFs) on Android 10+, with no permission; Android 9 and below ask
/// for the storage permission (after a one-line reason) and write into the
/// same folders. (`gal` needed a storage permission on Android 10, which the
/// app doesn't declare: "Permission needed".) iOS: Photos via `gal`, PDFs
/// through the system save dialog.
@lazySingleton
class SaveService {
  static const _channel = MethodChannel('com.swtnoa.flashdox/save');

  /// The last save's place, for the "Saved to …" snackbar and its Open.
  SavedTo? lastSaved;

  /// Android 9 and below without the storage permission yet: the caller
  /// shows a one-line reason before saving.
  Future<bool> needsPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('needsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Either<Failure, Unit>> saveImages(List<File> files) async {
    if (Platform.isAndroid) return _saveAndroid(files, image: true);
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final ok = await Gal.requestAccess(toAlbum: true);
        if (!ok) return const Left(PermissionFailure());
      }
      for (final f in files) {
        await Gal.putImage(f.path, album: 'Flash Dox');
      }
      lastSaved = (folder: 'Photos', uri: '', mime: 'image/*');
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

  /// A PDF (or any file): Download/Flash Dox on Android; the OS "save to"
  /// dialog on iOS (`CancelledFailure` when dismissed).
  Future<Either<Failure, String>> saveFileWithDialog(File file) async {
    if (Platform.isAndroid) return (await _saveAndroid([file], image: false)).map((_) => lastSaved?.uri ?? '');
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

  static String mimeOf(String path) => switch (p.extension(path).toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.txt' => 'text/plain',
    _ => 'image/jpeg',
  };

  Future<Either<Failure, Unit>> _saveAndroid(List<File> files, {required bool image}) async {
    try {
      for (final f in files) {
        final mime = mimeOf(f.path);
        final r = await _channel.invokeMapMethod<String, String>('save', {
          'path': f.path,
          'name': p.basename(f.path),
          'mime': mime,
          'image': image && mime.startsWith('image/'),
        });
        lastSaved = (folder: r?['folder'] ?? '', uri: r?['uri'] ?? '', mime: mime);
      }
      return const Right(unit);
    } on PlatformException catch (e) {
      return Left(e.code == 'permission' ? const PermissionFailure() : StorageFailure(e.message ?? e.code));
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  /// Opens the last saved file in another app.
  Future<void> openLast() async {
    final s = lastSaved;
    if (s == null || s.uri.isEmpty || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('open', {'uri': s.uri, 'mime': s.mime});
    } catch (_) {}
  }
}
