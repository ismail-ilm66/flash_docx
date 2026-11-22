import 'dart:async';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flash_dox/features/documents/presentation/cubit/home_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _Watch extends Mock implements WatchDocuments {}

class _Delete extends Mock implements DeleteDocument {}

class _Rename extends Mock implements RenameDocument {}

class _Folder extends Mock implements SetDocumentFolder {}

/// Round 10, P1-5: select several, delete with Undo.
void main() {
  ScanDocument doc(String id) => ScanDocument(
        id: id,
        title: id,
        mode: ScanMode.document,
        pages: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  late _Delete delete;
  late _Folder folder;
  late HomeCubit cubit;

  setUpAll(() => registerFallbackValue(DocFolder.other));

  setUp(() async {
    final watch = _Watch();
    delete = _Delete();
    folder = _Folder();
    when(() => watch(search: any(named: 'search'))).thenAnswer((_) => Stream.value([doc('a'), doc('b'), doc('c')]));
    when(() => delete(any())).thenAnswer((_) async => const Right(unit));
    cubit = HomeCubit(watch, delete, _Rename(), folder);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => cubit.close());

  test('long-press, toggle, select all, clear', () {
    cubit.startSelection('a');
    expect(cubit.state.selecting, isTrue);
    expect(cubit.state.selected, {'a'});
    cubit.toggleSelected('b');
    expect(cubit.state.selected, {'a', 'b'});
    cubit
      ..toggleSelected('a')
      ..toggleSelected('b');
    expect(cubit.state.selecting, isFalse, reason: 'the last one unticked ends selection');
    cubit
      ..startSelection('a')
      ..selectAll();
    expect(cubit.state.selected, {'a', 'b', 'c'});
    cubit.clearSelection();
    expect(cubit.state.selecting, isFalse);
    expect(cubit.state.selected, isEmpty);
  });

  test('delete hides at once and deletes only when committed; undo brings them back', () async {
    cubit
      ..startSelection('a')
      ..toggleSelected('b');
    final ids = cubit.hideSelected();
    expect(cubit.state.documents.map((d) => d.id), ['c']);
    verifyNever(() => delete(any()));

    cubit.undoDelete(ids);
    expect(cubit.state.documents.map((d) => d.id), ['a', 'b', 'c']);

    cubit.startSelection('a');
    await cubit.commitDelete(cubit.hideSelected());
    verify(() => delete('a')).called(1);
    verifyNever(() => delete('b'));
  });

  test('move to folder moves every selected document and ends selection', () async {
    when(() => folder(any(), any())).thenAnswer((_) async => const Right(unit));
    cubit
      ..startSelection('a')
      ..toggleSelected('c');
    expect(await cubit.moveSelected(DocFolder.bills), isNull);
    verify(() => folder('a', DocFolder.bills)).called(1);
    verify(() => folder('c', DocFolder.bills)).called(1);
    expect(cubit.state.selecting, isFalse);
  });
}
