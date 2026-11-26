import 'package:flash_dox/features/ocr/domain/recognize_page_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 11b, K2: lines joined into paragraphs.
void main() {
  test('soft line breaks and hyphens are joined; sentences, headings and blocks stay', () {
    const raw = 'Abstract\n'
        'Developing economies rely\n'
        'heavily on informal mar-\n'
        'kets. They grow fast.\n'
        'Results show:\n'
        'more trade.\n'
        '\n'
        'Second block';
    expect(
      RecognizePageText.joinParagraphs(raw),
      'Abstract\n'
      'Developing economies rely heavily on informal markets. They grow fast.\n'
      'Results show:\n'
      'more trade.\n'
      '\n'
      'Second block',
    );
  });
}
