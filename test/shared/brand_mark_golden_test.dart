import 'package:flash_dox/shared/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logo mark renders centred in its own colours', tags: ['golden'], (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF0F1012),
          child: Center(child: RepaintBoundary(child: SizedBox(width: 240, height: 240, child: Center(child: BrandMark(width: 195))))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(RepaintBoundary).last, matchesGoldenFile('goldens/brand_mark.png'));
  });
}
