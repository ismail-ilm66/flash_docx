import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// Round 11c, B2: while the user is still taking photos, each prepared page
/// gets its full-quality base and its first look (the default filter at
/// 1200 px) in the background, so Enhance opens on finished pages and the
/// viewer and Share find them ready. Background lane: a new photo's own
/// preparation always goes first.
@lazySingleton
class ScanWarmer {
  ScanWarmer(this._processor, this._files, this._bases);

  final ImageProcessor _processor;
  final FileStore _files;
  final CleanBaseService _bases;

  static bool cardMode(ScanMode m) => m != ScanMode.document && m != ScanMode.photo;

  Future<void> warm(ScanPage page, ScanMode mode) async {
    if (!CleanBaseService.covers(page.edits)) return;
    final card = cardMode(mode);
    try {
      await _bases.ensure(page, card: card);
      final look = _files.lookPath(page.id, page.originalPath, page.edits);
      if (File(look).existsSync()) return;
      await _processor.renderLookFromClean(
        _bases.previewPath(page, card: card),
        page.edits,
        outputPath: look,
        autoPath: _files.autoBasePath(page.id, page.originalPath, page.edits),
        priority: JobPriority.background,
      );
    } on Object catch (e) {
      // A page deleted or edited meanwhile: Enhance makes what it needs.
      debugPrint('[warm] ${page.id}: $e');
    }
  }
}
