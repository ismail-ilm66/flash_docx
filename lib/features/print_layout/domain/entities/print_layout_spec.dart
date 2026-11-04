import 'package:freezed_annotation/freezed_annotation.dart';

part 'print_layout_spec.freezed.dart';

enum PrintKind { idCard, passport }

enum PrintOutput { image, pdfDoubleSided, pdfOnePage }

@freezed
abstract class PrintLayoutSpec with _$PrintLayoutSpec {
  const factory PrintLayoutSpec({
    required PrintKind kind,
    required PrintOutput output,
    required int copies,
    required String frontPath,
    String? backPath,
    String? title,
  }) = _PrintLayoutSpec;
  const PrintLayoutSpec._();

  bool get hasBack => backPath != null;
}
