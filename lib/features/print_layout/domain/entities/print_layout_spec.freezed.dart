// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'print_layout_spec.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PrintLayoutSpec {

 PrintKind get kind; PrintOutput get output; int get copies; String get frontPath; String? get backPath; String? get title;
/// Create a copy of PrintLayoutSpec
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PrintLayoutSpecCopyWith<PrintLayoutSpec> get copyWith => _$PrintLayoutSpecCopyWithImpl<PrintLayoutSpec>(this as PrintLayoutSpec, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PrintLayoutSpec&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.output, output) || other.output == output)&&(identical(other.copies, copies) || other.copies == copies)&&(identical(other.frontPath, frontPath) || other.frontPath == frontPath)&&(identical(other.backPath, backPath) || other.backPath == backPath)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,kind,output,copies,frontPath,backPath,title);

@override
String toString() {
  return 'PrintLayoutSpec(kind: $kind, output: $output, copies: $copies, frontPath: $frontPath, backPath: $backPath, title: $title)';
}


}

/// @nodoc
abstract mixin class $PrintLayoutSpecCopyWith<$Res>  {
  factory $PrintLayoutSpecCopyWith(PrintLayoutSpec value, $Res Function(PrintLayoutSpec) _then) = _$PrintLayoutSpecCopyWithImpl;
@useResult
$Res call({
 PrintKind kind, PrintOutput output, int copies, String frontPath, String? backPath, String? title
});




}
/// @nodoc
class _$PrintLayoutSpecCopyWithImpl<$Res>
    implements $PrintLayoutSpecCopyWith<$Res> {
  _$PrintLayoutSpecCopyWithImpl(this._self, this._then);

  final PrintLayoutSpec _self;
  final $Res Function(PrintLayoutSpec) _then;

/// Create a copy of PrintLayoutSpec
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? output = null,Object? copies = null,Object? frontPath = null,Object? backPath = freezed,Object? title = freezed,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PrintKind,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as PrintOutput,copies: null == copies ? _self.copies : copies // ignore: cast_nullable_to_non_nullable
as int,frontPath: null == frontPath ? _self.frontPath : frontPath // ignore: cast_nullable_to_non_nullable
as String,backPath: freezed == backPath ? _self.backPath : backPath // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _PrintLayoutSpec extends PrintLayoutSpec {
  const _PrintLayoutSpec({required this.kind, required this.output, required this.copies, required this.frontPath, this.backPath, this.title}): super._();
  

@override final  PrintKind kind;
@override final  PrintOutput output;
@override final  int copies;
@override final  String frontPath;
@override final  String? backPath;
@override final  String? title;

/// Create a copy of PrintLayoutSpec
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PrintLayoutSpecCopyWith<_PrintLayoutSpec> get copyWith => __$PrintLayoutSpecCopyWithImpl<_PrintLayoutSpec>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PrintLayoutSpec&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.output, output) || other.output == output)&&(identical(other.copies, copies) || other.copies == copies)&&(identical(other.frontPath, frontPath) || other.frontPath == frontPath)&&(identical(other.backPath, backPath) || other.backPath == backPath)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,kind,output,copies,frontPath,backPath,title);

@override
String toString() {
  return 'PrintLayoutSpec(kind: $kind, output: $output, copies: $copies, frontPath: $frontPath, backPath: $backPath, title: $title)';
}


}

/// @nodoc
abstract mixin class _$PrintLayoutSpecCopyWith<$Res> implements $PrintLayoutSpecCopyWith<$Res> {
  factory _$PrintLayoutSpecCopyWith(_PrintLayoutSpec value, $Res Function(_PrintLayoutSpec) _then) = __$PrintLayoutSpecCopyWithImpl;
@override @useResult
$Res call({
 PrintKind kind, PrintOutput output, int copies, String frontPath, String? backPath, String? title
});




}
/// @nodoc
class __$PrintLayoutSpecCopyWithImpl<$Res>
    implements _$PrintLayoutSpecCopyWith<$Res> {
  __$PrintLayoutSpecCopyWithImpl(this._self, this._then);

  final _PrintLayoutSpec _self;
  final $Res Function(_PrintLayoutSpec) _then;

/// Create a copy of PrintLayoutSpec
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? output = null,Object? copies = null,Object? frontPath = null,Object? backPath = freezed,Object? title = freezed,}) {
  return _then(_PrintLayoutSpec(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PrintKind,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as PrintOutput,copies: null == copies ? _self.copies : copies // ignore: cast_nullable_to_non_nullable
as int,frontPath: null == frontPath ? _self.frontPath : frontPath // ignore: cast_nullable_to_non_nullable
as String,backPath: freezed == backPath ? _self.backPath : backPath // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
