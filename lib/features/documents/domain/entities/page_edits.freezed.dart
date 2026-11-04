// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'page_edits.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PageEdits {

/// null = full image.
 Quad? get crop; int get quarterTurns; FilterType get filter;/// -100..100
 double get brightness;/// -100..100
 double get contrast;
/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PageEditsCopyWith<PageEdits> get copyWith => _$PageEditsCopyWithImpl<PageEdits>(this as PageEdits, _$identity);

  /// Serializes this PageEdits to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PageEdits&&(identical(other.crop, crop) || other.crop == crop)&&(identical(other.quarterTurns, quarterTurns) || other.quarterTurns == quarterTurns)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.brightness, brightness) || other.brightness == brightness)&&(identical(other.contrast, contrast) || other.contrast == contrast));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,crop,quarterTurns,filter,brightness,contrast);

@override
String toString() {
  return 'PageEdits(crop: $crop, quarterTurns: $quarterTurns, filter: $filter, brightness: $brightness, contrast: $contrast)';
}


}

/// @nodoc
abstract mixin class $PageEditsCopyWith<$Res>  {
  factory $PageEditsCopyWith(PageEdits value, $Res Function(PageEdits) _then) = _$PageEditsCopyWithImpl;
@useResult
$Res call({
 Quad? crop, int quarterTurns, FilterType filter, double brightness, double contrast
});


$QuadCopyWith<$Res>? get crop;

}
/// @nodoc
class _$PageEditsCopyWithImpl<$Res>
    implements $PageEditsCopyWith<$Res> {
  _$PageEditsCopyWithImpl(this._self, this._then);

  final PageEdits _self;
  final $Res Function(PageEdits) _then;

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? crop = freezed,Object? quarterTurns = null,Object? filter = null,Object? brightness = null,Object? contrast = null,}) {
  return _then(_self.copyWith(
crop: freezed == crop ? _self.crop : crop // ignore: cast_nullable_to_non_nullable
as Quad?,quarterTurns: null == quarterTurns ? _self.quarterTurns : quarterTurns // ignore: cast_nullable_to_non_nullable
as int,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FilterType,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,
  ));
}
/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuadCopyWith<$Res>? get crop {
    if (_self.crop == null) {
    return null;
  }

  return $QuadCopyWith<$Res>(_self.crop!, (value) {
    return _then(_self.copyWith(crop: value));
  });
}
}



/// @nodoc
@JsonSerializable()

class _PageEdits extends PageEdits {
  const _PageEdits({this.crop, this.quarterTurns = 0, this.filter = FilterType.auto, this.brightness = 0, this.contrast = 0}): super._();
  factory _PageEdits.fromJson(Map<String, dynamic> json) => _$PageEditsFromJson(json);

/// null = full image.
@override final  Quad? crop;
@override@JsonKey() final  int quarterTurns;
@override@JsonKey() final  FilterType filter;
/// -100..100
@override@JsonKey() final  double brightness;
/// -100..100
@override@JsonKey() final  double contrast;

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PageEditsCopyWith<_PageEdits> get copyWith => __$PageEditsCopyWithImpl<_PageEdits>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PageEditsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PageEdits&&(identical(other.crop, crop) || other.crop == crop)&&(identical(other.quarterTurns, quarterTurns) || other.quarterTurns == quarterTurns)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.brightness, brightness) || other.brightness == brightness)&&(identical(other.contrast, contrast) || other.contrast == contrast));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,crop,quarterTurns,filter,brightness,contrast);

@override
String toString() {
  return 'PageEdits(crop: $crop, quarterTurns: $quarterTurns, filter: $filter, brightness: $brightness, contrast: $contrast)';
}


}

/// @nodoc
abstract mixin class _$PageEditsCopyWith<$Res> implements $PageEditsCopyWith<$Res> {
  factory _$PageEditsCopyWith(_PageEdits value, $Res Function(_PageEdits) _then) = __$PageEditsCopyWithImpl;
@override @useResult
$Res call({
 Quad? crop, int quarterTurns, FilterType filter, double brightness, double contrast
});


@override $QuadCopyWith<$Res>? get crop;

}
/// @nodoc
class __$PageEditsCopyWithImpl<$Res>
    implements _$PageEditsCopyWith<$Res> {
  __$PageEditsCopyWithImpl(this._self, this._then);

  final _PageEdits _self;
  final $Res Function(_PageEdits) _then;

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? crop = freezed,Object? quarterTurns = null,Object? filter = null,Object? brightness = null,Object? contrast = null,}) {
  return _then(_PageEdits(
crop: freezed == crop ? _self.crop : crop // ignore: cast_nullable_to_non_nullable
as Quad?,quarterTurns: null == quarterTurns ? _self.quarterTurns : quarterTurns // ignore: cast_nullable_to_non_nullable
as int,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FilterType,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuadCopyWith<$Res>? get crop {
    if (_self.crop == null) {
    return null;
  }

  return $QuadCopyWith<$Res>(_self.crop!, (value) {
    return _then(_self.copyWith(crop: value));
  });
}
}

// dart format on
