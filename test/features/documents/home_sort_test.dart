import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/cubit/home_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

ScanDocument _doc(String id, String title, int day) => ScanDocument(
      id: id,
      title: title,
      mode: ScanMode.document,
      pages: const [],
      createdAt: DateTime(2026, 1, day),
      updatedAt: DateTime(2026, 1, day),
    );

void main() {
  final docs = [_doc('a', 'rent agreement', 2), _doc('b', 'Bill', 5), _doc('c', 'Câble', 1)];

  test('latest puts the most recently updated first', () {
    expect(sortDocuments(docs, HomeSort.latest).map((d) => d.id), ['b', 'a', 'c']);
  });

  test('oldest reverses that', () {
    expect(sortDocuments(docs, HomeSort.oldest).map((d) => d.id), ['c', 'a', 'b']);
  });

  test('name sorts case-insensitively and leaves the input untouched', () {
    expect(sortDocuments(docs, HomeSort.name).map((d) => d.id), ['b', 'c', 'a']);
    expect(docs.map((d) => d.id), ['a', 'b', 'c']);
  });
}
