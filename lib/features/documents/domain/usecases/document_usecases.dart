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
