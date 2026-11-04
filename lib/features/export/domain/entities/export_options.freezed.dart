// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'export_options.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExportOptions {

 ExportFormat get format; ExportQuality get quality; PdfPageSize get pageSize; String get fileName;
/// Create a copy of ExportOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExportOptionsCopyWith<ExportOptions> get copyWith => _$ExportOptionsCopyWithImpl<ExportOptions>(this as ExportOptions, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOptions&&(identical(other.format, format) || other.format == format)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.fileName, fileName) || other.fileName == fileName));
}


@override
int get hashCode => Object.hash(runtimeType,format,quality,pageSize,fileName);

@override
String toString() {
  return 'ExportOptions(format: $format, quality: $quality, pageSize: $pageSize, fileName: $fileName)';
}


}

/// @nodoc
abstract mixin class $ExportOptionsCopyWith<$Res>  {
  factory $ExportOptionsCopyWith(ExportOptions value, $Res Function(ExportOptions) _then) = _$ExportOptionsCopyWithImpl;
@useResult
$Res call({
 ExportFormat format, ExportQuality quality, PdfPageSize pageSize, String fileName
});




}
/// @nodoc
class _$ExportOptionsCopyWithImpl<$Res>
    implements $ExportOptionsCopyWith<$Res> {
  _$ExportOptionsCopyWithImpl(this._self, this._then);

  final ExportOptions _self;
  final $Res Function(ExportOptions) _then;

/// Create a copy of ExportOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? format = null,Object? quality = null,Object? pageSize = null,Object? fileName = null,}) {
  return _then(_self.copyWith(
format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as ExportFormat,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as ExportQuality,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as PdfPageSize,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _ExportOptions extends ExportOptions {
  const _ExportOptions({this.format = ExportFormat.pdf, this.quality = ExportQuality.standard, this.pageSize = PdfPageSize.a4, this.fileName = ''}): super._();
  

@override@JsonKey() final  ExportFormat format;
@override@JsonKey() final  ExportQuality quality;
@override@JsonKey() final  PdfPageSize pageSize;
@override@JsonKey() final  String fileName;

/// Create a copy of ExportOptions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExportOptionsCopyWith<_ExportOptions> get copyWith => __$ExportOptionsCopyWithImpl<_ExportOptions>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExportOptions&&(identical(other.format, format) || other.format == format)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.fileName, fileName) || other.fileName == fileName));
}


@override
int get hashCode => Object.hash(runtimeType,format,quality,pageSize,fileName);

@override
String toString() {
  return 'ExportOptions(format: $format, quality: $quality, pageSize: $pageSize, fileName: $fileName)';
}


}

/// @nodoc
abstract mixin class _$ExportOptionsCopyWith<$Res> implements $ExportOptionsCopyWith<$Res> {
  factory _$ExportOptionsCopyWith(_ExportOptions value, $Res Function(_ExportOptions) _then) = __$ExportOptionsCopyWithImpl;
@override @useResult
$Res call({
 ExportFormat format, ExportQuality quality, PdfPageSize pageSize, String fileName
});




}
/// @nodoc
class __$ExportOptionsCopyWithImpl<$Res>
    implements _$ExportOptionsCopyWith<$Res> {
  __$ExportOptionsCopyWithImpl(this._self, this._then);

  final _ExportOptions _self;
  final $Res Function(_ExportOptions) _then;

/// Create a copy of ExportOptions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? format = null,Object? quality = null,Object? pageSize = null,Object? fileName = null,}) {
  return _then(_ExportOptions(
format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as ExportFormat,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as ExportQuality,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as PdfPageSize,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PdfOptions {

 PdfPageSize get pageSize; String? get title;
/// Create a copy of PdfOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PdfOptionsCopyWith<PdfOptions> get copyWith => _$PdfOptionsCopyWithImpl<PdfOptions>(this as PdfOptions, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PdfOptions&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,pageSize,title);

@override
String toString() {
  return 'PdfOptions(pageSize: $pageSize, title: $title)';
}


}

/// @nodoc
abstract mixin class $PdfOptionsCopyWith<$Res>  {
  factory $PdfOptionsCopyWith(PdfOptions value, $Res Function(PdfOptions) _then) = _$PdfOptionsCopyWithImpl;
@useResult
$Res call({
 PdfPageSize pageSize, String? title
});




}
/// @nodoc
class _$PdfOptionsCopyWithImpl<$Res>
    implements $PdfOptionsCopyWith<$Res> {
  _$PdfOptionsCopyWithImpl(this._self, this._then);

  final PdfOptions _self;
  final $Res Function(PdfOptions) _then;

/// Create a copy of PdfOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pageSize = null,Object? title = freezed,}) {
  return _then(_self.copyWith(
pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as PdfPageSize,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _PdfOptions implements PdfOptions {
  const _PdfOptions({this.pageSize = PdfPageSize.a4, this.title});
  

@override@JsonKey() final  PdfPageSize pageSize;
@override final  String? title;

/// Create a copy of PdfOptions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PdfOptionsCopyWith<_PdfOptions> get copyWith => __$PdfOptionsCopyWithImpl<_PdfOptions>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PdfOptions&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,pageSize,title);

@override
String toString() {
  return 'PdfOptions(pageSize: $pageSize, title: $title)';
}


}

/// @nodoc
abstract mixin class _$PdfOptionsCopyWith<$Res> implements $PdfOptionsCopyWith<$Res> {
  factory _$PdfOptionsCopyWith(_PdfOptions value, $Res Function(_PdfOptions) _then) = __$PdfOptionsCopyWithImpl;
@override @useResult
$Res call({
 PdfPageSize pageSize, String? title
});




}
/// @nodoc
class __$PdfOptionsCopyWithImpl<$Res>
    implements _$PdfOptionsCopyWith<$Res> {
  __$PdfOptionsCopyWithImpl(this._self, this._then);

  final _PdfOptions _self;
  final $Res Function(_PdfOptions) _then;

/// Create a copy of PdfOptions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pageSize = null,Object? title = freezed,}) {
  return _then(_PdfOptions(
pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as PdfPageSize,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
