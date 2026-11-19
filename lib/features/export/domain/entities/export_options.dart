import 'package:flash_dox/core/constants/sizes.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'export_options.freezed.dart';

enum ExportFormat { pdf, jpg, png }

enum ExportQuality { standard, high }

/// Round 8, P0-8: Auto (the default) fills A4 when the image is within 6 %
/// of its shape, else the page takes the image's shape at A4 width. A4 and
/// Letter fit the image inside; Fit to image is always image-shaped.
enum PdfPageSize {
  auto(null, null),
  a4(PaperMm.a4Width, PaperMm.a4Height),
  letter(PaperMm.letterWidth, PaperMm.letterHeight),
  fit(null, null)
  ;

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
    @Default(PdfPageSize.auto) PdfPageSize pageSize,
    @Default('') String fileName,
    @Default(ExportLayout.oneImage) ExportLayout layout,

    /// Max file size (feature 2), PDF only: shrink until the file is at most
    /// this many bytes. null = no limit.
    int? maxBytes,

    /// The user agreed to black and white because colour couldn't fit.
    @Default(false) bool grayscaleToFit,

    /// Passport photo: exact pixel size an online form asks for (null =
    /// full resolution). A different shape is centre-cropped to fill it.
    int? pixelWidth,
    int? pixelHeight,
  }) = _ExportOptions;
  const ExportOptions._();

  bool get isImage => format != ExportFormat.pdf;

  bool get hasPixelSize => pixelWidth != null && pixelHeight != null;
  String get extension => switch (format) {
    ExportFormat.pdf => 'pdf',
    ExportFormat.jpg => 'jpg',
    ExportFormat.png => 'png',
  };
}

@freezed
abstract class PdfOptions with _$PdfOptions {
  const factory PdfOptions({
    @Default(PdfPageSize.auto) PdfPageSize pageSize,
    String? title,
  }) = _PdfOptions;
}
