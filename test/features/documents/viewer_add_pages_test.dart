import 'dart:async';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/presentation/cubit/viewer_cubit.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _Watch extends Mock implements WatchDocument {}

class _Rename extends Mock implements RenameDocument {}

class _Delete extends Mock implements DeleteDocument {}

class _DeletePage extends Mock implements DeletePage {}

class _Reorder extends Mock implements ReorderPages {}

class _Add extends Mock implements AddPages {}

class _Render extends Mock implements PageRenderService {}

class _Previews extends Mock implements PreviewCache {}

class _Suggest extends Mock implements NameSuggestionActions {}

class _Folder extends Mock implements SetDocumentFolder {}

class _Move extends Mock implements MovePages {}

/// Round 11, P0-11: pages added from the viewer come back after Adjust
/// edges and Enhance; the viewer puts them in place and shows the first.
void main() {
  ScanPage pg(String id, int order, [FilterType f = FilterType.auto]) =>
      ScanPage(id: id, documentId: 'd', originalPath: '/$id.jpg', edits: PageEdits(filter: f), order: order);
  final now = DateTime(2026, 11, 26);
  ScanDocument doc(List<ScanPage> pages) => ScanDocument(id: 'd', title: 't', mode: ScanMode.document, pages: pages, createdAt: now, updatedAt: now);
  setUpAll(() {
    registerFallbackValue(doc(const []));
    registerFallbackValue(pg('x', 0));
  });


  late StreamController<ScanDocument?> docs;
  late _Reorder reorder;
  late ViewerCubit cubit;

  setUp(() {
    docs = StreamController<ScanDocument?>.broadcast();
    final watch = _Watch();
    when(() => watch(any())).thenAnswer((_) => docs.stream);
    reorder = _Reorder();
    when(() => reorder(any(), any())).thenAnswer((_) async => const Right(unit));
    final render = _Render();
    when(() => render.ensureCaches(any(), first: any(named: 'first'))).thenAnswer((_) async {});
    final previews = _Previews();
    when(() => previews.lookIfReady(any())).thenReturn(null);
    when(() => previews.handedOff(any())).thenReturn(null);
    cubit = ViewerCubit(watch, _Rename(), _Delete(), _DeletePage(), reorder, _Add(), render, previews, _Suggest(), _Folder(), _Move(), 'd');
  });

  tearDown(() async {
    await cubit.close();
    await docs.close();
  });

  test('new pages at the end: the first new page is shown', () async {
    docs.add(doc([pg('a', 0), pg('b', 1), pg('c', 2)]));
    await Future<void>.delayed(Duration.zero);
    final placed = cubit.placeNewPages(['n1', 'n2']);
    docs.add(doc([pg('a', 0), pg('b', 1), pg('c', 2), pg('n1', 3), pg('n2', 4)]));
    await placed;
    expect(cubit.state.current?.id, 'n1');
    verifyNever(() => reorder(any(), any()));
  });

  test('"Insert after this page": moved after the open page', () async {
    docs.add(doc([pg('a', 0), pg('b', 1), pg('c', 2), pg('n1', 3), pg('n2', 4)]));
    await Future<void>.delayed(Duration.zero);
    await cubit.placeNewPages(['n1', 'n2'], after: 'a');
    verify(() => reorder('d', ['a', 'n1', 'n2', 'b', 'c'])).called(1);
    expect(cubit.state.index, 1);
  });

  test('added pages start with the filter most pages use', () {
    expect(ViewerCubit.documentFilter([pg('a', 0, FilterType.bwPrint), pg('b', 1, FilterType.bwPrint), pg('c', 2)]), FilterType.bwPrint);
    expect(ViewerCubit.documentFilter(const []), isNull);
  });
}
