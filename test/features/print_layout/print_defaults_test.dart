import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/presentation/cubit/print_layout_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 10, P1-3: a full sheet by default, not one tiny card.
void main() {
  ScanDocument doc(ScanMode mode) => ScanDocument(
        id: 'd',
        title: 'ID',
        mode: mode,
        pages: [
          for (final (i, side) in [CardSide.front, CardSide.back].indexed)
            ScanPage(id: 'p$i', documentId: 'd', originalPath: '/x', edits: const PageEdits(), order: i, side: side),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('ID card: PDF double-sided first, 8 copies; PDF one page 4', () {
    final s = PrintLayoutState(document: doc(ScanMode.idCard));
    expect(s.allowedOutputs.first, PrintOutput.pdfDoubleSided);
    expect(s.defaultCopies(PrintOutput.pdfDoubleSided), 8);
    expect(s.defaultCopies(PrintOutput.pdfOnePage), 4);
    expect(s.defaultCopies(PrintOutput.image), 1);
  });

  test('locked copies are never the default', () {
    final s = PrintLayoutState(document: doc(ScanMode.idCard), moreCopiesUnlocked: false);
    expect(s.defaultCopies(PrintOutput.pdfDoubleSided), 2);
  });
}
