import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:injectable/injectable.dart';

@injectable
class WatchDocuments {
  WatchDocuments(this._repo);
  final DocumentRepository _repo;

  Stream<List<ScanDocument>> call({String? search}) =>
      _repo.watchAll(search: search);
}
