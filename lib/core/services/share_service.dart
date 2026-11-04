import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:share_plus/share_plus.dart';

@lazySingleton
class ShareService {
  ShareService(this._share);

  final SharePlus _share;

  Future<Either<Failure, Unit>> shareFiles(
    List<File> files, {
    String? subject,
  }) async {
    try {
      final r = await _share.share(
        ShareParams(
          files: files.map((f) => XFile(f.path)).toList(),
          subject: subject,
        ),
      );
      if (r.status == ShareResultStatus.dismissed) {
        return const Left(CancelledFailure());
      }
      return const Right(unit);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  Future<Either<Failure, Unit>> shareText(String text, {String? subject}) async {
    try {
      await _share.share(ShareParams(text: text, subject: subject));
      return const Right(unit);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
