import 'package:flash_dox/features/documents/domain/entities/enums.dart';
import 'package:flash_dox/features/documents/domain/entities/page_edits.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_page.freezed.dart';
part 'scan_page.g.dart';

@freezed
abstract class ScanPage with _$ScanPage {
  const factory ScanPage({
    required String id,
    required String documentId,
    required String originalPath,
    required PageEdits edits,
    required int order,
    /// ID card only.
    CardSide? side,
    /// Cache, rebuilt when edits change.
    String? processedPath,
    String? thumbPath,
    /// Cache, cleared when edits change.
    String? ocrText,
  }) = _ScanPage;
  const ScanPage._();

  factory ScanPage.fromJson(Map<String, dynamic> json) =>
      _$ScanPageFromJson(json);

  /// Returns a copy with new edits and invalidated caches.
  ScanPage withEdits(PageEdits e) => copyWith(
        edits: e,
        processedPath: null,
        thumbPath: null,
        ocrText: null,
      );

  String get displayPath => processedPath ?? originalPath;
}
