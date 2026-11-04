// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quad.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Pt {

 double get x; double get y;
/// Create a copy of Pt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PtCopyWith<Pt> get copyWith => _$PtCopyWithImpl<Pt>(this as Pt, _$identity);

  /// Serializes this Pt to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Pt&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y);

@override
String toString() {
  return 'Pt(x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class $PtCopyWith<$Res>  {
  factory $PtCopyWith(Pt value, $Res Function(Pt) _then) = _$PtCopyWithImpl;
@useResult
$Res call({
 double x, double y
});




}
/// @nodoc
class _$PtCopyWithImpl<$Res>
    implements $PtCopyWith<$Res> {
  _$PtCopyWithImpl(this._self, this._then);

  final Pt _self;
  final $Res Function(Pt) _then;

/// Create a copy of Pt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? x = null,Object? y = null,}) {
  return _then(_self.copyWith(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _Pt extends Pt {
  const _Pt(this.x, this.y): super._();
  factory _Pt.fromJson(Map<String, dynamic> json) => _$PtFromJson(json);

@override final  double x;
@override final  double y;

/// Create a copy of Pt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PtCopyWith<_Pt> get copyWith => __$PtCopyWithImpl<_Pt>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PtToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Pt&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y);

@override
String toString() {
  return 'Pt(x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class _$PtCopyWith<$Res> implements $PtCopyWith<$Res> {
  factory _$PtCopyWith(_Pt value, $Res Function(_Pt) _then) = __$PtCopyWithImpl;
@override @useResult
$Res call({
 double x, double y
});




}
/// @nodoc
class __$PtCopyWithImpl<$Res>
    implements _$PtCopyWith<$Res> {
  __$PtCopyWithImpl(this._self, this._then);

  final _Pt _self;
  final $Res Function(_Pt) _then;

/// Create a copy of Pt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,}) {
  return _then(_Pt(
null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$Quad {

 Pt get tl; Pt get tr; Pt get br; Pt get bl;
/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuadCopyWith<Quad> get copyWith => _$QuadCopyWithImpl<Quad>(this as Quad, _$identity);

  /// Serializes this Quad to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Quad&&(identical(other.tl, tl) || other.tl == tl)&&(identical(other.tr, tr) || other.tr == tr)&&(identical(other.br, br) || other.br == br)&&(identical(other.bl, bl) || other.bl == bl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,tl,tr,br,bl);

@override
String toString() {
  return 'Quad(tl: $tl, tr: $tr, br: $br, bl: $bl)';
}


}

/// @nodoc
abstract mixin class $QuadCopyWith<$Res>  {
  factory $QuadCopyWith(Quad value, $Res Function(Quad) _then) = _$QuadCopyWithImpl;
@useResult
$Res call({
 Pt tl, Pt tr, Pt br, Pt bl
});


$PtCopyWith<$Res> get tl;$PtCopyWith<$Res> get tr;$PtCopyWith<$Res> get br;$PtCopyWith<$Res> get bl;

}
/// @nodoc
class _$QuadCopyWithImpl<$Res>
    implements $QuadCopyWith<$Res> {
  _$QuadCopyWithImpl(this._self, this._then);

  final Quad _self;
  final $Res Function(Quad) _then;

/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tl = null,Object? tr = null,Object? br = null,Object? bl = null,}) {
  return _then(_self.copyWith(
tl: null == tl ? _self.tl : tl // ignore: cast_nullable_to_non_nullable
as Pt,tr: null == tr ? _self.tr : tr // ignore: cast_nullable_to_non_nullable
as Pt,br: null == br ? _self.br : br // ignore: cast_nullable_to_non_nullable
as Pt,bl: null == bl ? _self.bl : bl // ignore: cast_nullable_to_non_nullable
as Pt,
  ));
}
/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get tl {
  
  return $PtCopyWith<$Res>(_self.tl, (value) {
    return _then(_self.copyWith(tl: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get tr {
  
  return $PtCopyWith<$Res>(_self.tr, (value) {
    return _then(_self.copyWith(tr: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get br {
  
  return $PtCopyWith<$Res>(_self.br, (value) {
    return _then(_self.copyWith(br: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get bl {
  
  return $PtCopyWith<$Res>(_self.bl, (value) {
    return _then(_self.copyWith(bl: value));
  });
}
}



/// @nodoc
@JsonSerializable()

class _Quad extends Quad {
  const _Quad({required this.tl, required this.tr, required this.br, required this.bl}): super._();
  factory _Quad.fromJson(Map<String, dynamic> json) => _$QuadFromJson(json);

@override final  Pt tl;
@override final  Pt tr;
@override final  Pt br;
@override final  Pt bl;

/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuadCopyWith<_Quad> get copyWith => __$QuadCopyWithImpl<_Quad>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Quad&&(identical(other.tl, tl) || other.tl == tl)&&(identical(other.tr, tr) || other.tr == tr)&&(identical(other.br, br) || other.br == br)&&(identical(other.bl, bl) || other.bl == bl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,tl,tr,br,bl);

@override
String toString() {
  return 'Quad(tl: $tl, tr: $tr, br: $br, bl: $bl)';
}


}

/// @nodoc
abstract mixin class _$QuadCopyWith<$Res> implements $QuadCopyWith<$Res> {
  factory _$QuadCopyWith(_Quad value, $Res Function(_Quad) _then) = __$QuadCopyWithImpl;
@override @useResult
$Res call({
 Pt tl, Pt tr, Pt br, Pt bl
});


@override $PtCopyWith<$Res> get tl;@override $PtCopyWith<$Res> get tr;@override $PtCopyWith<$Res> get br;@override $PtCopyWith<$Res> get bl;

}
/// @nodoc
class __$QuadCopyWithImpl<$Res>
    implements _$QuadCopyWith<$Res> {
  __$QuadCopyWithImpl(this._self, this._then);

  final _Quad _self;
  final $Res Function(_Quad) _then;

/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tl = null,Object? tr = null,Object? br = null,Object? bl = null,}) {
  return _then(_Quad(
tl: null == tl ? _self.tl : tl // ignore: cast_nullable_to_non_nullable
as Pt,tr: null == tr ? _self.tr : tr // ignore: cast_nullable_to_non_nullable
as Pt,br: null == br ? _self.br : br // ignore: cast_nullable_to_non_nullable
as Pt,bl: null == bl ? _self.bl : bl // ignore: cast_nullable_to_non_nullable
as Pt,
  ));
}

/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get tl {
  
  return $PtCopyWith<$Res>(_self.tl, (value) {
    return _then(_self.copyWith(tl: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get tr {
  
  return $PtCopyWith<$Res>(_self.tr, (value) {
    return _then(_self.copyWith(tr: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get br {
  
  return $PtCopyWith<$Res>(_self.br, (value) {
    return _then(_self.copyWith(br: value));
  });
}/// Create a copy of Quad
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PtCopyWith<$Res> get bl {
  
  return $PtCopyWith<$Res>(_self.bl, (value) {
    return _then(_self.copyWith(bl: value));
  });
}
}

// dart format on
