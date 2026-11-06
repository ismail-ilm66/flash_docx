// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'page_overlay.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PageOverlay {

 String get id; OverlayKind get kind; String get imagePath; double get left; double get top; double get width; double get height; InkColor get ink;
/// Create a copy of PageOverlay
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PageOverlayCopyWith<PageOverlay> get copyWith => _$PageOverlayCopyWithImpl<PageOverlay>(this as PageOverlay, _$identity);

  /// Serializes this PageOverlay to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PageOverlay&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.imagePath, imagePath) || other.imagePath == imagePath)&&(identical(other.left, left) || other.left == left)&&(identical(other.top, top) || other.top == top)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.ink, ink) || other.ink == ink));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,imagePath,left,top,width,height,ink);

@override
String toString() {
  return 'PageOverlay(id: $id, kind: $kind, imagePath: $imagePath, left: $left, top: $top, width: $width, height: $height, ink: $ink)';
}


}

/// @nodoc
abstract mixin class $PageOverlayCopyWith<$Res>  {
  factory $PageOverlayCopyWith(PageOverlay value, $Res Function(PageOverlay) _then) = _$PageOverlayCopyWithImpl;
@useResult
$Res call({
 String id, OverlayKind kind, String imagePath, double left, double top, double width, double height, InkColor ink
});




}
/// @nodoc
class _$PageOverlayCopyWithImpl<$Res>
    implements $PageOverlayCopyWith<$Res> {
  _$PageOverlayCopyWithImpl(this._self, this._then);

  final PageOverlay _self;
  final $Res Function(PageOverlay) _then;

/// Create a copy of PageOverlay
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? imagePath = null,Object? left = null,Object? top = null,Object? width = null,Object? height = null,Object? ink = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as OverlayKind,imagePath: null == imagePath ? _self.imagePath : imagePath // ignore: cast_nullable_to_non_nullable
as String,left: null == left ? _self.left : left // ignore: cast_nullable_to_non_nullable
as double,top: null == top ? _self.top : top // ignore: cast_nullable_to_non_nullable
as double,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,ink: null == ink ? _self.ink : ink // ignore: cast_nullable_to_non_nullable
as InkColor,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _PageOverlay implements PageOverlay {
  const _PageOverlay({required this.id, required this.kind, required this.imagePath, required this.left, required this.top, required this.width, required this.height, this.ink = InkColor.blue});
  factory _PageOverlay.fromJson(Map<String, dynamic> json) => _$PageOverlayFromJson(json);

@override final  String id;
@override final  OverlayKind kind;
@override final  String imagePath;
@override final  double left;
@override final  double top;
@override final  double width;
@override final  double height;
@override@JsonKey() final  InkColor ink;

/// Create a copy of PageOverlay
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PageOverlayCopyWith<_PageOverlay> get copyWith => __$PageOverlayCopyWithImpl<_PageOverlay>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PageOverlayToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PageOverlay&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.imagePath, imagePath) || other.imagePath == imagePath)&&(identical(other.left, left) || other.left == left)&&(identical(other.top, top) || other.top == top)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.ink, ink) || other.ink == ink));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,imagePath,left,top,width,height,ink);

@override
String toString() {
  return 'PageOverlay(id: $id, kind: $kind, imagePath: $imagePath, left: $left, top: $top, width: $width, height: $height, ink: $ink)';
}


}

/// @nodoc
abstract mixin class _$PageOverlayCopyWith<$Res> implements $PageOverlayCopyWith<$Res> {
  factory _$PageOverlayCopyWith(_PageOverlay value, $Res Function(_PageOverlay) _then) = __$PageOverlayCopyWithImpl;
@override @useResult
$Res call({
 String id, OverlayKind kind, String imagePath, double left, double top, double width, double height, InkColor ink
});




}
/// @nodoc
class __$PageOverlayCopyWithImpl<$Res>
    implements _$PageOverlayCopyWith<$Res> {
  __$PageOverlayCopyWithImpl(this._self, this._then);

  final _PageOverlay _self;
  final $Res Function(_PageOverlay) _then;

/// Create a copy of PageOverlay
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? imagePath = null,Object? left = null,Object? top = null,Object? width = null,Object? height = null,Object? ink = null,}) {
  return _then(_PageOverlay(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as OverlayKind,imagePath: null == imagePath ? _self.imagePath : imagePath // ignore: cast_nullable_to_non_nullable
as String,left: null == left ? _self.left : left // ignore: cast_nullable_to_non_nullable
as double,top: null == top ? _self.top : top // ignore: cast_nullable_to_non_nullable
as double,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,ink: null == ink ? _self.ink : ink // ignore: cast_nullable_to_non_nullable
as InkColor,
  ));
}


}

// dart format on
