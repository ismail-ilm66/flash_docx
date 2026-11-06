// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'name_suggestion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NameSuggestion {

 String get title; DocFolder get folder;/// What it looks like, for "Looks like an electricity bill".
 String get kind; bool get dismissed;
/// Create a copy of NameSuggestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NameSuggestionCopyWith<NameSuggestion> get copyWith => _$NameSuggestionCopyWithImpl<NameSuggestion>(this as NameSuggestion, _$identity);

  /// Serializes this NameSuggestion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NameSuggestion&&(identical(other.title, title) || other.title == title)&&(identical(other.folder, folder) || other.folder == folder)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.dismissed, dismissed) || other.dismissed == dismissed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,folder,kind,dismissed);

@override
String toString() {
  return 'NameSuggestion(title: $title, folder: $folder, kind: $kind, dismissed: $dismissed)';
}


}

/// @nodoc
abstract mixin class $NameSuggestionCopyWith<$Res>  {
  factory $NameSuggestionCopyWith(NameSuggestion value, $Res Function(NameSuggestion) _then) = _$NameSuggestionCopyWithImpl;
@useResult
$Res call({
 String title, DocFolder folder, String kind, bool dismissed
});




}
/// @nodoc
class _$NameSuggestionCopyWithImpl<$Res>
    implements $NameSuggestionCopyWith<$Res> {
  _$NameSuggestionCopyWithImpl(this._self, this._then);

  final NameSuggestion _self;
  final $Res Function(NameSuggestion) _then;

/// Create a copy of NameSuggestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? folder = null,Object? kind = null,Object? dismissed = null,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as DocFolder,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,dismissed: null == dismissed ? _self.dismissed : dismissed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _NameSuggestion implements NameSuggestion {
  const _NameSuggestion({required this.title, required this.folder, required this.kind, this.dismissed = false});
  factory _NameSuggestion.fromJson(Map<String, dynamic> json) => _$NameSuggestionFromJson(json);

@override final  String title;
@override final  DocFolder folder;
/// What it looks like, for "Looks like an electricity bill".
@override final  String kind;
@override@JsonKey() final  bool dismissed;

/// Create a copy of NameSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NameSuggestionCopyWith<_NameSuggestion> get copyWith => __$NameSuggestionCopyWithImpl<_NameSuggestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NameSuggestionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NameSuggestion&&(identical(other.title, title) || other.title == title)&&(identical(other.folder, folder) || other.folder == folder)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.dismissed, dismissed) || other.dismissed == dismissed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,folder,kind,dismissed);

@override
String toString() {
  return 'NameSuggestion(title: $title, folder: $folder, kind: $kind, dismissed: $dismissed)';
}


}

/// @nodoc
abstract mixin class _$NameSuggestionCopyWith<$Res> implements $NameSuggestionCopyWith<$Res> {
  factory _$NameSuggestionCopyWith(_NameSuggestion value, $Res Function(_NameSuggestion) _then) = __$NameSuggestionCopyWithImpl;
@override @useResult
$Res call({
 String title, DocFolder folder, String kind, bool dismissed
});




}
/// @nodoc
class __$NameSuggestionCopyWithImpl<$Res>
    implements _$NameSuggestionCopyWith<$Res> {
  __$NameSuggestionCopyWithImpl(this._self, this._then);

  final _NameSuggestion _self;
  final $Res Function(_NameSuggestion) _then;

/// Create a copy of NameSuggestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? folder = null,Object? kind = null,Object? dismissed = null,}) {
  return _then(_NameSuggestion(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,folder: null == folder ? _self.folder : folder // ignore: cast_nullable_to_non_nullable
as DocFolder,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,dismissed: null == dismissed ? _self.dismissed : dismissed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
