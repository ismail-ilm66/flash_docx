import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:fpdart/fpdart.dart';

abstract interface class DocumentRepository {
  Stream<List<ScanDocument>> watchAll({String? search});
  Stream<ScanDocument?> watch(String id);
  Future<Either<Failure, ScanDocument>> get(String id);
  Future<Either<Failure, ScanDocument>> create({
    required ScanMode mode,
    required List<ScanPage> pages,
    String? title,
  });
  Future<Either<Failure, Unit>> rename(String id, String title);

  /// Moves a document to a Home folder (feature 3).
  Future<Either<Failure, Unit>> setFolder(String id, DocFolder folder);

  /// Stores (or clears) the smart-name suggestion. Doesn't touch updatedAt:
  /// a background suggestion mustn't reorder Home.
  Future<Either<Failure, Unit>> setSuggestion(String id, NameSuggestion? suggestion);
  Future<Either<Failure, Unit>> addPages(String id, List<ScanPage> pages);
  Future<Either<Failure, Unit>> reorder(String id, List<String> pageIds);

  /// Round 11, P0-13: moves pages (in this order) to the end of another
  /// document, or of a new one of the same kind when [toDocumentId] is
  /// null. A document left without pages is deleted. Returns the target's
  /// id.
  Future<Either<Failure, String>> movePages(List<String> pageIds, {String? toDocumentId});
  Future<Either<Failure, Unit>> updatePage(ScanPage page);
  Future<Either<Failure, Unit>> updatePages(List<ScanPage> pages);
  Future<Either<Failure, Unit>> deletePage(String pageId);
  Future<Either<Failure, Unit>> delete(String id);
  Future<Either<Failure, Unit>> logActivity(String id, ActivityType type);
  Future<Either<Failure, int>> storageUsedBytes();
}
