import 'package:flash_dox/core/constants/sizes.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'export_options.freezed.dart';

enum ExportFormat { pdf, jpg, png }

enum ExportQuality { standard, high }

enum PdfPageSize {
  a4(PaperMm.a4Width, PaperMm.a4Height),
  letter(PaperMm.letterWidth, PaperMm.letterHeight),
  fit(null, null);

  const PdfPageSize(this.widthMm, this.heightMm);

  final double? widthMm;
  final double? heightMm;
}

enum ExportTarget { share, saveToPhone }

/// ID card / passport only: both sides as one picture, or one file per page.
enum ExportLayout { oneImage, separate }

@freezed
abstract class ExportOptions with _$ExportOptions {
  const factory ExportOptions({
    @Default(ExportFormat.pdf) ExportFormat format,
    @Default(ExportQuality.standard) ExportQuality quality,
    @Default(PdfPageSize.a4) PdfPageSize pageSize,
    @Default('') String fileName,
    @Default(ExportLayout.oneImage) ExportLayout layout,
  }) = _ExportOptions;
  const ExportOptions._();

  bool get isImage => format != ExportFormat.pdf;
  String get extension => switch (format) {
        ExportFormat.pdf => 'pdf',
        ExportFormat.jpg => 'jpg',
        ExportFormat.png => 'png',
      };
}

@freezed
abstract class PdfOptions with _$PdfOptions {
  const factory PdfOptions({
    @Default(PdfPageSize.a4) PdfPageSize pageSize,
    String? title,
  }) = _PdfOptions;
}
