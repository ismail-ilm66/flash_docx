import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single completes after one capture', () {
    final r = ScanModeRules.of(ScanMode.single);
    expect(r.isComplete(0), isFalse);
    expect(r.isComplete(1), isTrue);
    expect(r.canFinishEarly, isFalse);
    expect(r.aspectRatio, isNull);
  });

  test('batch allows finishing early', () {
    final r = ScanModeRules.of(ScanMode.batch);
    expect(r.canFinishEarly, isTrue);
    expect(r.guideLabel(3), GuideLabel.batchPage);
  });

  test('id card guides front then back and snaps to ID-1', () {
    final r = ScanModeRules.of(ScanMode.idCard);
    expect(r.guideLabel(0), GuideLabel.front);
    expect(r.guideLabel(1), GuideLabel.back);
    expect(r.isComplete(2), isTrue);
    expect(r.sides, [CardSide.front, CardSide.back]);
    expect(r.aspectRatio, closeTo(CardMm.id1Aspect, 1e-9));
  });

  test('passport snaps to ID-3', () {
    final r = ScanModeRules.of(ScanMode.passport);
    expect(r.aspectRatio, closeTo(125 / 88, 1e-9));
    expect(r.maxPages, 1);
  });
}
