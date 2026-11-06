// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page_overlay.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PageOverlay _$PageOverlayFromJson(Map<String, dynamic> json) => _PageOverlay(
  id: json['id'] as String,
  kind: $enumDecode(_$OverlayKindEnumMap, json['kind']),
  imagePath: json['imagePath'] as String,
  left: (json['left'] as num).toDouble(),
  top: (json['top'] as num).toDouble(),
  width: (json['width'] as num).toDouble(),
  height: (json['height'] as num).toDouble(),
  ink: $enumDecodeNullable(_$InkColorEnumMap, json['ink']) ?? InkColor.blue,
);

Map<String, dynamic> _$PageOverlayToJson(_PageOverlay instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': _$OverlayKindEnumMap[instance.kind]!,
      'imagePath': instance.imagePath,
      'left': instance.left,
      'top': instance.top,
      'width': instance.width,
      'height': instance.height,
      'ink': _$InkColorEnumMap[instance.ink]!,
    };

const _$OverlayKindEnumMap = {
  OverlayKind.signature: 'signature',
  OverlayKind.date: 'date',
};

const _$InkColorEnumMap = {
  InkColor.black: 'black',
  InkColor.blue: 'blue',
  InkColor.original: 'original',
};
