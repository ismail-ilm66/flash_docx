// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ScanDocument _$ScanDocumentFromJson(Map<String, dynamic> json) =>
    _ScanDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      mode: $enumDecode(_$ScanModeEnumMap, json['mode']),
      pages: (json['pages'] as List<dynamic>)
          .map((e) => ScanPage.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastActivity: json['lastActivity'] == null
          ? null
          : Activity.fromJson(json['lastActivity'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ScanDocumentToJson(_ScanDocument instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'mode': _$ScanModeEnumMap[instance.mode]!,
      'pages': instance.pages.map((e) => e.toJson()).toList(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'lastActivity': instance.lastActivity?.toJson(),
    };

const _$ScanModeEnumMap = {
  ScanMode.single: 'single',
  ScanMode.batch: 'batch',
  ScanMode.idCard: 'idCard',
  ScanMode.passport: 'passport',
};
