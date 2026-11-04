// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scan_page.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ScanPage {

 String get id; String get documentId; String get originalPath; PageEdits get edits; int get order;/// ID card only.
 CardSide? get side;/// Cache, rebuilt when edits change.
 String? get processedPath; String? get thumbPath;/// Cache, cleared when edits change.
 String? get ocrText;/// Transient: false when auto edge detection fell back to a default crop
/// and the user should be nudged to drag the corners. Not persisted.
@JsonKey(includeFromJson: false, includeToJson: false) bool get edgesDetected;
/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanPageCopyWith<ScanPage> get copyWith => _$ScanPageCopyWithImpl<ScanPage>(this as ScanPage, _$identity);

  /// Serializes this ScanPage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanPage&&(identical(other.id, id) || other.id == id)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.originalPath, originalPath) || other.originalPath == originalPath)&&(identical(other.edits, edits) || other.edits == edits)&&(identical(other.order, order) || other.order == order)&&(identical(other.side, side) || other.side == side)&&(identical(other.processedPath, processedPath) || other.processedPath == processedPath)&&(identical(other.thumbPath, thumbPath) || other.thumbPath == thumbPath)&&(identical(other.ocrText, ocrText) || other.ocrText == ocrText)&&(identical(other.edgesDetected, edgesDetected) || other.edgesDetected == edgesDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,documentId,originalPath,edits,order,side,processedPath,thumbPath,ocrText,edgesDetected);

@override
String toString() {
  return 'ScanPage(id: $id, documentId: $documentId, originalPath: $originalPath, edits: $edits, order: $order, side: $side, processedPath: $processedPath, thumbPath: $thumbPath, ocrText: $ocrText, edgesDetected: $edgesDetected)';
}


}

/// @nodoc
abstract mixin class $ScanPageCopyWith<$Res>  {
  factory $ScanPageCopyWith(ScanPage value, $Res Function(ScanPage) _then) = _$ScanPageCopyWithImpl;
@useResult
$Res call({
 String id, String documentId, String originalPath, PageEdits edits, int order, CardSide? side, String? processedPath, String? thumbPath, String? ocrText,@JsonKey(includeFromJson: false, includeToJson: false) bool edgesDetected
});


$PageEditsCopyWith<$Res> get edits;

}
/// @nodoc
class _$ScanPageCopyWithImpl<$Res>
    implements $ScanPageCopyWith<$Res> {
  _$ScanPageCopyWithImpl(this._self, this._then);

  final ScanPage _self;
  final $Res Function(ScanPage) _then;

/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? documentId = null,Object? originalPath = null,Object? edits = null,Object? order = null,Object? side = freezed,Object? processedPath = freezed,Object? thumbPath = freezed,Object? ocrText = freezed,Object? edgesDetected = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,originalPath: null == originalPath ? _self.originalPath : originalPath // ignore: cast_nullable_to_non_nullable
as String,edits: null == edits ? _self.edits : edits // ignore: cast_nullable_to_non_nullable
as PageEdits,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,side: freezed == side ? _self.side : side // ignore: cast_nullable_to_non_nullable
as CardSide?,processedPath: freezed == processedPath ? _self.processedPath : processedPath // ignore: cast_nullable_to_non_nullable
as String?,thumbPath: freezed == thumbPath ? _self.thumbPath : thumbPath // ignore: cast_nullable_to_non_nullable
as String?,ocrText: freezed == ocrText ? _self.ocrText : ocrText // ignore: cast_nullable_to_non_nullable
as String?,edgesDetected: null == edgesDetected ? _self.edgesDetected : edgesDetected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PageEditsCopyWith<$Res> get edits {
  
  return $PageEditsCopyWith<$Res>(_self.edits, (value) {
    return _then(_self.copyWith(edits: value));
  });
}
}



/// @nodoc
@JsonSerializable()

class _ScanPage extends ScanPage {
  const _ScanPage({required this.id, required this.documentId, required this.originalPath, required this.edits, required this.order, this.side, this.processedPath, this.thumbPath, this.ocrText, @JsonKey(includeFromJson: false, includeToJson: false) this.edgesDetected = true}): super._();
  factory _ScanPage.fromJson(Map<String, dynamic> json) => _$ScanPageFromJson(json);

@override final  String id;
@override final  String documentId;
@override final  String originalPath;
@override final  PageEdits edits;
@override final  int order;
/// ID card only.
@override final  CardSide? side;
/// Cache, rebuilt when edits change.
@override final  String? processedPath;
@override final  String? thumbPath;
/// Cache, cleared when edits change.
@override final  String? ocrText;
/// Transient: false when auto edge detection fell back to a default crop
/// and the user should be nudged to drag the corners. Not persisted.
@override@JsonKey(includeFromJson: false, includeToJson: false) final  bool edgesDetected;

/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScanPageCopyWith<_ScanPage> get copyWith => __$ScanPageCopyWithImpl<_ScanPage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ScanPageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ScanPage&&(identical(other.id, id) || other.id == id)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.originalPath, originalPath) || other.originalPath == originalPath)&&(identical(other.edits, edits) || other.edits == edits)&&(identical(other.order, order) || other.order == order)&&(identical(other.side, side) || other.side == side)&&(identical(other.processedPath, processedPath) || other.processedPath == processedPath)&&(identical(other.thumbPath, thumbPath) || other.thumbPath == thumbPath)&&(identical(other.ocrText, ocrText) || other.ocrText == ocrText)&&(identical(other.edgesDetected, edgesDetected) || other.edgesDetected == edgesDetected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,documentId,originalPath,edits,order,side,processedPath,thumbPath,ocrText,edgesDetected);

@override
String toString() {
  return 'ScanPage(id: $id, documentId: $documentId, originalPath: $originalPath, edits: $edits, order: $order, side: $side, processedPath: $processedPath, thumbPath: $thumbPath, ocrText: $ocrText, edgesDetected: $edgesDetected)';
}


}

/// @nodoc
abstract mixin class _$ScanPageCopyWith<$Res> implements $ScanPageCopyWith<$Res> {
  factory _$ScanPageCopyWith(_ScanPage value, $Res Function(_ScanPage) _then) = __$ScanPageCopyWithImpl;
@override @useResult
$Res call({
 String id, String documentId, String originalPath, PageEdits edits, int order, CardSide? side, String? processedPath, String? thumbPath, String? ocrText,@JsonKey(includeFromJson: false, includeToJson: false) bool edgesDetected
});


@override $PageEditsCopyWith<$Res> get edits;

}
/// @nodoc
class __$ScanPageCopyWithImpl<$Res>
    implements _$ScanPageCopyWith<$Res> {
  __$ScanPageCopyWithImpl(this._self, this._then);

  final _ScanPage _self;
  final $Res Function(_ScanPage) _then;

/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? documentId = null,Object? originalPath = null,Object? edits = null,Object? order = null,Object? side = freezed,Object? processedPath = freezed,Object? thumbPath = freezed,Object? ocrText = freezed,Object? edgesDetected = null,}) {
  return _then(_ScanPage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,originalPath: null == originalPath ? _self.originalPath : originalPath // ignore: cast_nullable_to_non_nullable
as String,edits: null == edits ? _self.edits : edits // ignore: cast_nullable_to_non_nullable
as PageEdits,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,side: freezed == side ? _self.side : side // ignore: cast_nullable_to_non_nullable
as CardSide?,processedPath: freezed == processedPath ? _self.processedPath : processedPath // ignore: cast_nullable_to_non_nullable
as String?,thumbPath: freezed == thumbPath ? _self.thumbPath : thumbPath // ignore: cast_nullable_to_non_nullable
as String?,ocrText: freezed == ocrText ? _self.ocrText : ocrText // ignore: cast_nullable_to_non_nullable
as String?,edgesDetected: null == edgesDetected ? _self.edgesDetected : edgesDetected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ScanPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PageEditsCopyWith<$Res> get edits {
  
  return $PageEditsCopyWith<$Res>(_self.edits, (value) {
    return _then(_self.copyWith(edits: value));
  });
}
}

// dart format on
