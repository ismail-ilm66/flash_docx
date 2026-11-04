// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page_edits.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PageEdits _$PageEditsFromJson(Map<String, dynamic> json) => _PageEdits(
  crop: json['crop'] == null
      ? null
      : Quad.fromJson(json['crop'] as Map<String, dynamic>),
  quarterTurns: (json['quarterTurns'] as num?)?.toInt() ?? 0,
  filter:
      $enumDecodeNullable(_$FilterTypeEnumMap, json['filter']) ??
      FilterType.auto,
  brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
  contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic> _$PageEditsToJson(_PageEdits instance) =>
    <String, dynamic>{
      'crop': instance.crop?.toJson(),
      'quarterTurns': instance.quarterTurns,
      'filter': _$FilterTypeEnumMap[instance.filter]!,
      'brightness': instance.brightness,
      'contrast': instance.contrast,
    };

const _$FilterTypeEnumMap = {
  FilterType.original: 'original',
  FilterType.auto: 'auto',
  FilterType.colorBoost: 'colorBoost',
  FilterType.grayscale: 'grayscale',
  FilterType.bwPrint: 'bwPrint',
};
