import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/documents/domain/entities/enums.dart';

/// Strategy per scan mode. The camera UI reads these rules; there is no
/// `if (mode == …)` in widgets.
abstract interface class ScanModeRules {
  ScanMode get mode;

  /// null = unlimited.
  int? get maxPages;

  /// ID card = [front, back]; others null.
  List<CardSide>? get sides;

  /// Aspect ratio the detected quad is snapped to, null = free.
  double? get aspectRatio;

  /// Key for the guide label shown above the shutter.
  GuideLabel guideLabel(int captured);

  bool isComplete(int captured);

  /// Whether the user may finish early (batch) or must capture all (ID card).
  bool get canFinishEarly;

  static ScanModeRules of(ScanMode mode) => switch (mode) {
        ScanMode.single => const SingleRules(),
        ScanMode.batch => const BatchRules(),
        ScanMode.idCard => const IdCardRules(),
        ScanMode.passport => const PassportRules(),
      };
}

enum GuideLabel { single, batchPage, front, back, passport }

class SingleRules implements ScanModeRules {
  const SingleRules();
  @override
  ScanMode get mode => ScanMode.single;
  @override
  int? get maxPages => 1;
  @override
  List<CardSide>? get sides => null;
  @override
  double? get aspectRatio => null;
  @override
  GuideLabel guideLabel(int captured) => GuideLabel.single;
  @override
  bool isComplete(int captured) => captured >= 1;
  @override
  bool get canFinishEarly => false;
}

class BatchRules implements ScanModeRules {
  const BatchRules();
  @override
  ScanMode get mode => ScanMode.batch;
  @override
  int? get maxPages => Limits.maxBatchPages;
  @override
  List<CardSide>? get sides => null;
  @override
  double? get aspectRatio => null;
  @override
  GuideLabel guideLabel(int captured) => GuideLabel.batchPage;
  @override
  bool isComplete(int captured) => captured >= Limits.maxBatchPages;
  @override
  bool get canFinishEarly => true;
}

class IdCardRules implements ScanModeRules {
  const IdCardRules();
  @override
  ScanMode get mode => ScanMode.idCard;
  @override
  int? get maxPages => 2;
  @override
  List<CardSide>? get sides => const [CardSide.front, CardSide.back];
  @override
  double? get aspectRatio => CardMm.id1Aspect;
  @override
  GuideLabel guideLabel(int captured) =>
      captured == 0 ? GuideLabel.front : GuideLabel.back;
  @override
  bool isComplete(int captured) => captured >= 2;
  @override
  bool get canFinishEarly => false;
}

class PassportRules implements ScanModeRules {
  const PassportRules();
  @override
  ScanMode get mode => ScanMode.passport;
  @override
  int? get maxPages => 1;
  @override
  List<CardSide>? get sides => null;
  @override
  double? get aspectRatio => CardMm.id3Aspect;
  @override
  GuideLabel guideLabel(int captured) => GuideLabel.passport;
  @override
  bool isComplete(int captured) => captured >= 1;
  @override
  bool get canFinishEarly => false;
}
