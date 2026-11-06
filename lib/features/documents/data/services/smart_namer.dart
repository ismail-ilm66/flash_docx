import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/documents/domain/smart_rules.dart';
import 'package:flash_dox/features/ocr/domain/recognize_page_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// Smart names (feature 3): after a scan is saved, reads page 1 on the phone
/// (English OCR, the page's dedicated OCR image) and stores a suggested
/// title and folder for the viewer's banner. Never renames anything itself.
@lazySingleton
class SmartNamer {
  SmartNamer(this._repo, this._ocr);

  final DocumentRepository _repo;
  final RecognizePageText _ocr;

  SmartRules? _rules;

  /// Tests use the asset file directly.
  @visibleForTesting
  void useRules(SmartRules rules) => _rules = rules;

  Future<SmartRules> _load() async => _rules ??= SmartRules.fromJson(await rootBundle.loadString('assets/smart_rules.json'));

  Future<void> suggestFor(String documentId) async {
    try {
      final doc = (await _repo.get(documentId)).toNullable();
      final cover = doc?.cover;
      if (doc == null || cover == null || doc.suggestion != null) return;
      final text = (await _ocr(cover)).getOrElse((_) => '');
      final s = (await _load()).match(text, doc.mode, doc.createdAt, pages: doc.pages.length);
      debugPrint('[smart] ${doc.title} -> ${s?.title} (${s?.folder.name})');
      if (s == null || (s.title == doc.title && s.folder == doc.folder)) return;
      await _repo.setSuggestion(documentId, s);
    } on Object catch (e) {
      debugPrint('[smart] failed: $e');
    }
  }
}
