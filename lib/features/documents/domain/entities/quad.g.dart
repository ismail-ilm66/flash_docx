// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quad.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Pt _$PtFromJson(Map<String, dynamic> json) =>
    _Pt((json['x'] as num).toDouble(), (json['y'] as num).toDouble());

Map<String, dynamic> _$PtToJson(_Pt instance) => <String, dynamic>{
  'x': instance.x,
  'y': instance.y,
};

_Quad _$QuadFromJson(Map<String, dynamic> json) => _Quad(
  tl: Pt.fromJson(json['tl'] as Map<String, dynamic>),
  tr: Pt.fromJson(json['tr'] as Map<String, dynamic>),
  br: Pt.fromJson(json['br'] as Map<String, dynamic>),
  bl: Pt.fromJson(json['bl'] as Map<String, dynamic>),
);

Map<String, dynamic> _$QuadToJson(_Quad instance) => <String, dynamic>{
  'tl': instance.tl,
  'tr': instance.tr,
  'br': instance.br,
  'bl': instance.bl,
};
