import 'dart:io';

import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';

abstract interface class PdfBuilder {
  /// One image per page, centred and scaled to fit [PdfOptions.pageSize].
  Future<File> fromPages(
    List<String> imagePaths,
    PdfOptions options, {
    required String outputPath,
  });

  /// Passport photos (feature 5): [photoPath] at each item's place and real
  /// size on [paper], with dashed cut lines when [cutLines].
  Future<File> photoSheet({
    required String photoPath,
    required List<PlacedItem> items,
    required PhotoPaper paper,
    required bool cutLines,
    required String title,
    required String outputPath,
  });

  /// ID card / passport print sheet at real size (A4, millimetres).
  Future<File> printSheet(
    PrintLayoutSpec spec, {
    required String outputPath,
  });
}
