// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Activity _$ActivityFromJson(Map<String, dynamic> json) => _Activity(
  id: json['id'] as String,
  documentId: json['documentId'] as String,
  type: $enumDecode(_$ActivityTypeEnumMap, json['type']),
  at: DateTime.parse(json['at'] as String),
);

Map<String, dynamic> _$ActivityToJson(_Activity instance) => <String, dynamic>{
  'id': instance.id,
  'documentId': instance.documentId,
  'type': _$ActivityTypeEnumMap[instance.type]!,
  'at': instance.at.toIso8601String(),
};

const _$ActivityTypeEnumMap = {
  ActivityType.created: 'created',
  ActivityType.edited: 'edited',
  ActivityType.sharedPdf: 'sharedPdf',
  ActivityType.sharedImages: 'sharedImages',
  ActivityType.savedToPhone: 'savedToPhone',
  ActivityType.textCopied: 'textCopied',
  ActivityType.printLayout: 'printLayout',
};
