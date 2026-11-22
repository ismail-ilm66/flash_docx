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
  outputAspect: (json['outputAspect'] as num?)?.toDouble(),
  overlays:
      (json['overlays'] as List<dynamic>?)
          ?.map((e) => PageOverlay.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PageOverlay>[],
  photoWidthMm: (json['photoWidthMm'] as num?)?.toDouble(),
  photoHeightMm: (json['photoHeightMm'] as num?)?.toDouble(),
  photoBackground:
      $enumDecodeNullable(
        _$PhotoBackgroundEnumMap,
        json['photoBackground'],
        unknownValue: PhotoBackground.darkBlue,
      ) ??
      PhotoBackground.original,
  backgroundMaskPath: json['backgroundMaskPath'] as String?,
  photoEnhance:
      $enumDecodeNullable(
        _$PhotoEnhanceEnumMap,
        json['photoEnhance'],
        unknownValue: PhotoEnhance.off,
      ) ??
      PhotoEnhance.off,
);

Map<String, dynamic> _$PageEditsToJson(_PageEdits instance) =>
    <String, dynamic>{
      'crop': instance.crop?.toJson(),
      'quarterTurns': instance.quarterTurns,
      'filter': _$FilterTypeEnumMap[instance.filter]!,
      'brightness': instance.brightness,
      'contrast': instance.contrast,
      'outputAspect': instance.outputAspect,
      'overlays': instance.overlays.map((e) => e.toJson()).toList(),
      'photoWidthMm': instance.photoWidthMm,
      'photoHeightMm': instance.photoHeightMm,
      'photoBackground': _$PhotoBackgroundEnumMap[instance.photoBackground]!,
      'backgroundMaskPath': instance.backgroundMaskPath,
      'photoEnhance': _$PhotoEnhanceEnumMap[instance.photoEnhance]!,
    };

const _$FilterTypeEnumMap = {
  FilterType.original: 'original',
  FilterType.auto: 'auto',
  FilterType.idColor: 'idColor',
  FilterType.colorBoost: 'colorBoost',
  FilterType.grayscale: 'grayscale',
  FilterType.bwPrint: 'bwPrint',
};

const _$PhotoBackgroundEnumMap = {
  PhotoBackground.original: 'original',
  PhotoBackground.white: 'white',
  PhotoBackground.darkBlue: 'darkBlue',
  PhotoBackground.offWhite: 'offWhite',
  PhotoBackground.paleBlue: 'paleBlue',
  PhotoBackground.skyBlue: 'skyBlue',
};

const _$PhotoEnhanceEnumMap = {
  PhotoEnhance.off: 'off',
  PhotoEnhance.natural: 'natural',
  PhotoEnhance.smooth: 'smooth',
};
