// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scan_document.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ScanDocument {

 String get id; String get title; ScanMode get mode; List<ScanPage> get pages; DateTime get createdAt; DateTime get updatedAt; Activity? get lastActivity; DocFolder get folder; NameSuggestion? get suggestion;/// Bytes of all page files on disk (originals and caches).
 int get sizeBytes;
/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanDocumentCopyWith<ScanDocument> get copyWith => _$ScanDocumentCopyWithImpl<ScanDocument>(this as ScanDocument, _$identity);

  /// Serializes this ScanDocument to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanDocument&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other.pages, pages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastActivity, lastActivity) || other.lastActivity == lastActivity)&&(identical(other.folder, folder) || other.folder == folder)&&(identical(other.suggestion, suggestion) || other.suggestion == suggestion)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,mode,const DeepCollectionEquality().hash(pages),createdAt,updatedAt,lastActivity,folder,suggestion,sizeBytes);

@override
String toString() {
  return 'ScanDocument(id: $id, title: $title, mode: $mode, pages: $pages, createdAt: $createdAt, updatedAt: $updatedAt, lastActivity: $lastActivity, folder: $folder, suggestion: $suggestion, sizeBytes: $sizeBytes)';
}


}

/// @nodoc
abstract mixin class $ScanDocumentCopyWith<$Res>  {
  factory $ScanDocumentCopyWith(ScanDocument value, $Res Function(ScanDocument) _then) = _$ScanDocumentCopyWithImpl;
@useResult
$Res call({
 String id, String title, ScanMode mode, List<ScanPage> pages, DateTime createdAt, DateTime updatedAt, Activity? lastActivity, DocFolder folder, NameSuggestion? suggestion, int sizeBytes
});


$ActivityCopyWith<$Res>? get lastActivity;$NameSuggestionCopyWith<$Res>? get suggestion;

}
/// @nodoc
class _$ScanDocumentCopyWithImpl<$Res>
    implements $ScanDocumentCopyWith<$Res> {
  _$ScanDocumentCopyWithImpl(this._self, this._then);

  final ScanDocument _self;
  final $Res Function(ScanDocument) _then;

/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? mode = null,Object? pages = null,Object? createdAt = null,Object? updatedAt = null,Object? lastActivity = freezed,Object? folder = null,Object? suggestion = freezed,Object? sizeBytes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ScanMode,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as List<ScanPage>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastActivity: freezed == lastActivity ? _self.lastActivity : lastActivity // ignore: cast_nullable_to_non_nullable
as Activity?,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as DocFolder,suggestion: freezed == suggestion ? _self.suggestion : suggestion // ignore: cast_nullable_to_non_nullable
as NameSuggestion?,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityCopyWith<$Res>? get lastActivity {
    if (_self.lastActivity == null) {
    return null;
  }

  return $ActivityCopyWith<$Res>(_self.lastActivity!, (value) {
    return _then(_self.copyWith(lastActivity: value));
  });
}/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NameSuggestionCopyWith<$Res>? get suggestion {
    if (_self.suggestion == null) {
    return null;
  }

  return $NameSuggestionCopyWith<$Res>(_self.suggestion!, (value) {
    return _then(_self.copyWith(suggestion: value));
  });
}
}



/// @nodoc
@JsonSerializable()

class _ScanDocument extends ScanDocument {
  const _ScanDocument({required this.id, required this.title, required this.mode, required final  List<ScanPage> pages, required this.createdAt, required this.updatedAt, this.lastActivity, this.folder = DocFolder.other, this.suggestion, this.sizeBytes = 0}): _pages = pages,super._();
  factory _ScanDocument.fromJson(Map<String, dynamic> json) => _$ScanDocumentFromJson(json);

@override final  String id;
@override final  String title;
@override final  ScanMode mode;
 final  List<ScanPage> _pages;
@override List<ScanPage> get pages {
  if (_pages is EqualUnmodifiableListView) return _pages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pages);
}

@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  Activity? lastActivity;
@override@JsonKey() final  DocFolder folder;
@override final  NameSuggestion? suggestion;
/// Bytes of all page files on disk (originals and caches).
@override@JsonKey() final  int sizeBytes;

/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScanDocumentCopyWith<_ScanDocument> get copyWith => __$ScanDocumentCopyWithImpl<_ScanDocument>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ScanDocumentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ScanDocument&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other._pages, _pages)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastActivity, lastActivity) || other.lastActivity == lastActivity)&&(identical(other.folder, folder) || other.folder == folder)&&(identical(other.suggestion, suggestion) || other.suggestion == suggestion)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,mode,const DeepCollectionEquality().hash(_pages),createdAt,updatedAt,lastActivity,folder,suggestion,sizeBytes);

@override
String toString() {
  return 'ScanDocument(id: $id, title: $title, mode: $mode, pages: $pages, createdAt: $createdAt, updatedAt: $updatedAt, lastActivity: $lastActivity, folder: $folder, suggestion: $suggestion, sizeBytes: $sizeBytes)';
}


}

/// @nodoc
abstract mixin class _$ScanDocumentCopyWith<$Res> implements $ScanDocumentCopyWith<$Res> {
  factory _$ScanDocumentCopyWith(_ScanDocument value, $Res Function(_ScanDocument) _then) = __$ScanDocumentCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, ScanMode mode, List<ScanPage> pages, DateTime createdAt, DateTime updatedAt, Activity? lastActivity, DocFolder folder, NameSuggestion? suggestion, int sizeBytes
});


@override $ActivityCopyWith<$Res>? get lastActivity;@override $NameSuggestionCopyWith<$Res>? get suggestion;

}
/// @nodoc
class __$ScanDocumentCopyWithImpl<$Res>
    implements _$ScanDocumentCopyWith<$Res> {
  __$ScanDocumentCopyWithImpl(this._self, this._then);

  final _ScanDocument _self;
  final $Res Function(_ScanDocument) _then;

/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? mode = null,Object? pages = null,Object? createdAt = null,Object? updatedAt = null,Object? lastActivity = freezed,Object? folder = null,Object? suggestion = freezed,Object? sizeBytes = null,}) {
  return _then(_ScanDocument(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ScanMode,pages: null == pages ? _self._pages : pages // ignore: cast_nullable_to_non_nullable
as List<ScanPage>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,lastActivity: freezed == lastActivity ? _self.lastActivity : lastActivity // ignore: cast_nullable_to_non_nullable
as Activity?,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as DocFolder,suggestion: freezed == suggestion ? _self.suggestion : suggestion // ignore: cast_nullable_to_non_nullable
as NameSuggestion?,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityCopyWith<$Res>? get lastActivity {
    if (_self.lastActivity == null) {
    return null;
  }

  return $ActivityCopyWith<$Res>(_self.lastActivity!, (value) {
    return _then(_self.copyWith(lastActivity: value));
  });
}/// Create a copy of ScanDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NameSuggestionCopyWith<$Res>? get suggestion {
    if (_self.suggestion == null) {
    return null;
  }

  return $NameSuggestionCopyWith<$Res>(_self.suggestion!, (value) {
    return _then(_self.copyWith(suggestion: value));
  });
}
}

// dart format on
