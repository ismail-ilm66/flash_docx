import 'package:flash_dox/features/documents/domain/entities/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'name_suggestion.freezed.dart';
part 'name_suggestion.g.dart';

/// Smart names (feature 3): what page 1 looks like, offered on the viewer's
/// banner. Never applied without the user tapping Apply.
@freezed
abstract class NameSuggestion with _$NameSuggestion {
  const factory NameSuggestion({
    required String title,
    required DocFolder folder,

    /// What it looks like, for "Looks like an electricity bill".
    required String kind,
    @Default(false) bool dismissed,
  }) = _NameSuggestion;

  factory NameSuggestion.fromJson(Map<String, dynamic> json) => _$NameSuggestionFromJson(json);
}
