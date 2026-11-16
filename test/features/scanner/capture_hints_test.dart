import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 6, P1-1: what the camera and Adjust edges learn from each shot.
void main() {
  ScanPage page(String id) => ScanPage(id: id, documentId: '', originalPath: '$id.jpg', edits: const PageEdits(), order: 0);

  test('a dark last shot shows "Low light" until a brighter one or the flash', () {
    const dark = Capture('a', 'a.jpg', brightness: 55);
    const bright = Capture('b', 'b.jpg', brightness: 140);
    expect(const ScanSessionState(mode: ScanMode.document, captures: [dark]).lowLight, isTrue);
    expect(const ScanSessionState(mode: ScanMode.document, captures: [dark, bright]).lowLight, isFalse);
    expect(const ScanSessionState(mode: ScanMode.document, captures: [dark], flashOn: true).lowLight, isFalse);
    expect(const ScanSessionState(mode: ScanMode.document).lowLight, isFalse, reason: 'no shot yet');
  });

  test('partly blurry shots are passed on to Adjust edges by page id', () {
    final s = ScanSessionState(
      mode: ScanMode.document,
      captures: [
        Capture('a', 'a.jpg', page: page('p1'), blurry: true),
        Capture('b', 'b.jpg', page: page('p2')),
        const Capture('c', 'c.jpg', blurry: true), // still processing
      ],
    );
    expect(s.blurryPages, {'p1'});
  });
}
