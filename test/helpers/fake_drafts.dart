import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
import 'package:mocktail/mocktail.dart';

/// Records what a bloc asks the draft store to do (round 7, P0-3).
class FakeDrafts extends Fake implements DraftService {
  final saved = <List<ScanPage>>[];
  int finishedCalls = 0;
  int discardCalls = 0;

  @override
  Future<void> save(ScanMode mode, List<ScanPage> pages) async => saved.add(pages);

  @override
  Future<void> finished() async => finishedCalls++;

  @override
  Future<void> discard() async => discardCalls++;
}
