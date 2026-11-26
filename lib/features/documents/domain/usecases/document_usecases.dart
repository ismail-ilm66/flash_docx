import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

@injectable
class WatchDocument {
  WatchDocument(this._repo);
  final DocumentRepository _repo;
  Stream<ScanDocument?> call(String id) => _repo.watch(id);
}

@injectable
class GetDocument {
  GetDocument(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, ScanDocument>> call(String id) => _repo.get(id);
}

@injectable
class CreateDocument {
  CreateDocument(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, ScanDocument>> call({
    required ScanMode mode,
    required List<ScanPage> pages,
    String? title,
  }) =>
      _repo.create(mode: mode, pages: pages, title: title);
}

@injectable
class RenameDocument {
  RenameDocument(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id, String title) =>
      _repo.rename(id, title.trim());
}

@injectable
class DeleteDocument {
  DeleteDocument(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id) => _repo.delete(id);
}

@injectable
class AddPages {
  AddPages(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id, List<ScanPage> pages) =>
      _repo.addPages(id, pages);
}

@injectable
class ReorderPages {
  ReorderPages(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id, List<String> pageIds) =>
      _repo.reorder(id, pageIds);
}

@injectable
class MovePages {
  MovePages(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, String>> call(List<String> pageIds, {String? toDocumentId}) =>
      _repo.movePages(pageIds, toDocumentId: toDocumentId);
}

@injectable
class DeletePage {
  DeletePage(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String pageId) => _repo.deletePage(pageId);
}

@injectable
class UpdatePages {
  UpdatePages(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(List<ScanPage> pages) =>
      _repo.updatePages(pages);
}

@injectable
class LogActivity {
  LogActivity(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id, ActivityType type) =>
      _repo.logActivity(id, type);
}

@injectable
class GetStorageUsed {
  GetStorageUsed(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, int>> call() => _repo.storageUsedBytes();
}

/// Moves a document to a Home folder (feature 3).
@injectable
class SetDocumentFolder {
  SetDocumentFolder(this._repo);
  final DocumentRepository _repo;
  Future<Either<Failure, Unit>> call(String id, DocFolder folder) => _repo.setFolder(id, folder);
}

/// The viewer banner's Apply / ✕ (feature 3). Apply renames and files the
/// document; either way the banner doesn't come back.
@injectable
class NameSuggestionActions {
  NameSuggestionActions(this._repo);
  final DocumentRepository _repo;

  Future<Either<Failure, Unit>> apply(ScanDocument doc) async {
    final s = doc.suggestion;
    if (s == null) return const Right(unit);
    final renamed = await _repo.rename(doc.id, s.title);
    if (renamed.isLeft()) return renamed;
    final moved = await _repo.setFolder(doc.id, s.folder);
    if (moved.isLeft()) return moved;
    return _repo.setSuggestion(doc.id, s.copyWith(dismissed: true));
  }

  Future<Either<Failure, Unit>> dismiss(ScanDocument doc) async {
    final s = doc.suggestion;
    if (s == null) return const Right(unit);
    return _repo.setSuggestion(doc.id, s.copyWith(dismissed: true));
  }
}
