import 'dart:io';

import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// One-time fixes to documents made by older builds (round 11b), run at
/// start-up before Home:
/// - G2: an ID card is exactly front and back. A document with more sides
///   is split into documents of 2 sides each, "ID card – front & back (2)",
///   "(3)", …
/// - H1: a passport photo document is one page, the photo. Extra pages
///   with a photo become their own documents; pages without one (the blank
///   page 2 some builds made) are deleted.
@lazySingleton
class DocumentFixups {
  DocumentFixups(this._repo, this._prefs);

  final DocumentRepository _repo;
  final PrefsService _prefs;

  static const _doneKey = 'fixups_11b';

  Future<void> run() async {
    if (_prefs.flag(_doneKey)) return;
    try {
      final docs = await _repo.watchAll().first;
      for (final doc in docs) {
        if (doc.mode == ScanMode.idCard && doc.pages.length > 2) await _split(doc, 2, 'ID card – front & back');
        if (doc.mode == ScanMode.photo && doc.pages.length > 1) await _onePhoto(doc);
      }
      await _prefs.setFlag(_doneKey);
    } catch (e) {
      debugPrint('[fixups] $e');
    }
  }

  Future<void> _split(ScanDocument doc, int size, String title) async {
    final pages = doc.sortedPages;
    var n = 2;
    for (var i = size; i < pages.length; i += size) {
      final chunk = pages.sublist(i, (i + size).clamp(0, pages.length));
      final moved = await _repo.movePages([for (final p in chunk) p.id]);
      final id = moved.toNullable();
      if (id != null) await _repo.rename(id, '$title ($n)');
      n++;
    }
  }

  Future<void> _onePhoto(ScanDocument doc) async {
    final pages = doc.sortedPages;
    var n = 2;
    for (final p in pages.skip(1)) {
      if (!File(p.originalPath).existsSync()) {
        await _repo.deletePage(p.id);
        continue;
      }
      final id = (await _repo.movePages([p.id])).toNullable();
      if (id != null) await _repo.rename(id, '${doc.title} ($n)');
      n++;
    }
  }
}
