// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ScanPage _$ScanPageFromJson(Map<String, dynamic> json) => _ScanPage(
  id: json['id'] as String,
  documentId: json['documentId'] as String,
  originalPath: json['originalPath'] as String,
  edits: PageEdits.fromJson(json['edits'] as Map<String, dynamic>),
  order: (json['order'] as num).toInt(),
  side: $enumDecodeNullable(_$CardSideEnumMap, json['side']),
  processedPath: json['processedPath'] as String?,
  thumbPath: json['thumbPath'] as String?,
  ocrText: json['ocrText'] as String?,
);

Map<String, dynamic> _$ScanPageToJson(_ScanPage instance) => <String, dynamic>{
  'id': instance.id,
  'documentId': instance.documentId,
  'originalPath': instance.originalPath,
  'edits': instance.edits,
  'order': instance.order,
  'side': _$CardSideEnumMap[instance.side],
  'processedPath': instance.processedPath,
  'thumbPath': instance.thumbPath,
  'ocrText': instance.ocrText,
};

const _$CardSideEnumMap = {CardSide.front: 'front', CardSide.back: 'back'};
