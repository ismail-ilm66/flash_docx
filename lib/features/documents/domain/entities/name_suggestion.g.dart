// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'name_suggestion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NameSuggestion _$NameSuggestionFromJson(Map<String, dynamic> json) =>
    _NameSuggestion(
      title: json['title'] as String,
      folder: $enumDecode(_$DocFolderEnumMap, json['folder']),
      kind: json['kind'] as String,
      dismissed: json['dismissed'] as bool? ?? false,
    );

Map<String, dynamic> _$NameSuggestionToJson(_NameSuggestion instance) =>
    <String, dynamic>{
      'title': instance.title,
      'folder': _$DocFolderEnumMap[instance.folder]!,
      'kind': instance.kind,
      'dismissed': instance.dismissed,
    };

const _$DocFolderEnumMap = {
  DocFolder.other: 'other',
  DocFolder.bills: 'bills',
  DocFolder.ids: 'ids',
  DocFolder.education: 'education',
  DocFolder.receipts: 'receipts',
};
