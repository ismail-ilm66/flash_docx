import 'package:flash_dox/features/documents/domain/entities/activity.dart';
import 'package:flash_dox/features/documents/domain/entities/enums.dart';
import 'package:flash_dox/features/documents/domain/entities/scan_page.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_document.freezed.dart';
part 'scan_document.g.dart';

@freezed
abstract class ScanDocument with _$ScanDocument {
  const factory ScanDocument({
    required String id,
    required String title,
    required ScanMode mode,
    required List<ScanPage> pages,
    required DateTime createdAt,
    required DateTime updatedAt,
    Activity? lastActivity,
  }) = _ScanDocument;
  const ScanDocument._();

  factory ScanDocument.fromJson(Map<String, dynamic> json) =>
      _$ScanDocumentFromJson(json);

  List<ScanPage> get sortedPages =>
      [...pages]..sort((a, b) => a.order.compareTo(b.order));

  ScanPage? get cover => sortedPages.firstOrNull;

  ScanPage? pageOfSide(CardSide side) =>
      pages.where((p) => p.side == side).firstOrNull;
}
