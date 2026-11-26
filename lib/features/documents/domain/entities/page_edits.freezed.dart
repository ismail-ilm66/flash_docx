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
 double get contrast;/// ID card / passport: the warp is forced to this width / height (real
/// card shape, landscape), as in the reference `warp()`. null = free.
 double? get outputAspect;/// Signatures and date stamps (feature 4), drawn over the finished page.
 List<PageOverlay> get overlays;/// Passport photo (feature 5): the print size in millimetres.
 double? get photoWidthMm; double? get photoHeightMm;/// Passport photo background: the person mask for the whole upright
/// photo (8-bit PNG, any size; sharper inside the crop, see
/// `BackgroundSegmenter.maskFor`) and the colour behind them. The
/// mask is also kept with an original background, for Enhance. Applied as
/// the crop is rendered, so every output gets it.
@JsonKey(unknownEnumValue: PhotoBackground.darkBlue) PhotoBackground get photoBackground; String? get backgroundMaskPath;/// Passport photo touch-up, before the background. Off for photos saved
/// before it existed, so they keep their look.
@JsonKey(unknownEnumValue: PhotoEnhance.off) PhotoEnhance get photoEnhance;/// Round 11b, P1-14: the face in a passport photo (ML Kit), as
/// [x0, y0, x1, y1] fractions of the upright photo, for Enhance's
/// face brightening. Null: found from the person mask instead.
 List<double>? get faceBox;/// Round 11, P0-14: the user placed the corners in Adjust edges, so the
/// bent-page warp keeps them exactly (only the sides may bend). Pages
/// saved before it existed read as true: their corners never move.
@JsonKey(defaultValue: true) bool get cornersFixed;/// Round 11, P1-11: "Remove" was tapped for the fingers found on this
/// page; [fingerMaskPath] is their mask (8-bit PNG, the cropped and
/// turned page at any size). Applied after the filter, so a filter
/// change keeps them removed.
 bool get fingersRemoved; String? get fingerMaskPath;
/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PageEditsCopyWith<PageEdits> get copyWith => _$PageEditsCopyWithImpl<PageEdits>(this as PageEdits, _$identity);

  /// Serializes this PageEdits to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PageEdits&&(identical(other.crop, crop) || other.crop == crop)&&(identical(other.quarterTurns, quarterTurns) || other.quarterTurns == quarterTurns)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.brightness, brightness) || other.brightness == brightness)&&(identical(other.contrast, contrast) || other.contrast == contrast)&&(identical(other.outputAspect, outputAspect) || other.outputAspect == outputAspect)&&const DeepCollectionEquality().equals(other.overlays, overlays)&&(identical(other.photoWidthMm, photoWidthMm) || other.photoWidthMm == photoWidthMm)&&(identical(other.photoHeightMm, photoHeightMm) || other.photoHeightMm == photoHeightMm)&&(identical(other.photoBackground, photoBackground) || other.photoBackground == photoBackground)&&(identical(other.backgroundMaskPath, backgroundMaskPath) || other.backgroundMaskPath == backgroundMaskPath)&&(identical(other.photoEnhance, photoEnhance) || other.photoEnhance == photoEnhance)&&const DeepCollectionEquality().equals(other.faceBox, faceBox)&&(identical(other.cornersFixed, cornersFixed) || other.cornersFixed == cornersFixed)&&(identical(other.fingersRemoved, fingersRemoved) || other.fingersRemoved == fingersRemoved)&&(identical(other.fingerMaskPath, fingerMaskPath) || other.fingerMaskPath == fingerMaskPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,crop,quarterTurns,filter,brightness,contrast,outputAspect,const DeepCollectionEquality().hash(overlays),photoWidthMm,photoHeightMm,photoBackground,backgroundMaskPath,photoEnhance,const DeepCollectionEquality().hash(faceBox),cornersFixed,fingersRemoved,fingerMaskPath);

@override
String toString() {
  return 'PageEdits(crop: $crop, quarterTurns: $quarterTurns, filter: $filter, brightness: $brightness, contrast: $contrast, outputAspect: $outputAspect, overlays: $overlays, photoWidthMm: $photoWidthMm, photoHeightMm: $photoHeightMm, photoBackground: $photoBackground, backgroundMaskPath: $backgroundMaskPath, photoEnhance: $photoEnhance, faceBox: $faceBox, cornersFixed: $cornersFixed, fingersRemoved: $fingersRemoved, fingerMaskPath: $fingerMaskPath)';
}


}

/// @nodoc
abstract mixin class $PageEditsCopyWith<$Res>  {
  factory $PageEditsCopyWith(PageEdits value, $Res Function(PageEdits) _then) = _$PageEditsCopyWithImpl;
@useResult
$Res call({
 Quad? crop, int quarterTurns, FilterType filter, double brightness, double contrast, double? outputAspect, List<PageOverlay> overlays, double? photoWidthMm, double? photoHeightMm,@JsonKey(unknownEnumValue: PhotoBackground.darkBlue) PhotoBackground photoBackground, String? backgroundMaskPath,@JsonKey(unknownEnumValue: PhotoEnhance.off) PhotoEnhance photoEnhance, List<double>? faceBox,@JsonKey(defaultValue: true) bool cornersFixed, bool fingersRemoved, String? fingerMaskPath
});




}
/// @nodoc
class _$PageEditsCopyWithImpl<$Res>
    implements $PageEditsCopyWith<$Res> {
  _$PageEditsCopyWithImpl(this._self, this._then);

  final PageEdits _self;
  final $Res Function(PageEdits) _then;

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? crop = freezed,Object? quarterTurns = null,Object? filter = null,Object? brightness = null,Object? contrast = null,Object? outputAspect = freezed,Object? overlays = null,Object? photoWidthMm = freezed,Object? photoHeightMm = freezed,Object? photoBackground = null,Object? backgroundMaskPath = freezed,Object? photoEnhance = null,Object? faceBox = freezed,Object? cornersFixed = null,Object? fingersRemoved = null,Object? fingerMaskPath = freezed,}) {
  return _then(_self.copyWith(
crop: freezed == crop ? _self.crop : crop // ignore: cast_nullable_to_non_nullable
as Quad?,quarterTurns: null == quarterTurns ? _self.quarterTurns : quarterTurns // ignore: cast_nullable_to_non_nullable
as int,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FilterType,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,outputAspect: freezed == outputAspect ? _self.outputAspect : outputAspect // ignore: cast_nullable_to_non_nullable
as double?,overlays: null == overlays ? _self.overlays : overlays // ignore: cast_nullable_to_non_nullable
as List<PageOverlay>,photoWidthMm: freezed == photoWidthMm ? _self.photoWidthMm : photoWidthMm // ignore: cast_nullable_to_non_nullable
as double?,photoHeightMm: freezed == photoHeightMm ? _self.photoHeightMm : photoHeightMm // ignore: cast_nullable_to_non_nullable
as double?,photoBackground: null == photoBackground ? _self.photoBackground : photoBackground // ignore: cast_nullable_to_non_nullable
as PhotoBackground,backgroundMaskPath: freezed == backgroundMaskPath ? _self.backgroundMaskPath : backgroundMaskPath // ignore: cast_nullable_to_non_nullable
as String?,photoEnhance: null == photoEnhance ? _self.photoEnhance : photoEnhance // ignore: cast_nullable_to_non_nullable
as PhotoEnhance,faceBox: freezed == faceBox ? _self.faceBox : faceBox // ignore: cast_nullable_to_non_nullable
as List<double>?,cornersFixed: null == cornersFixed ? _self.cornersFixed : cornersFixed // ignore: cast_nullable_to_non_nullable
as bool,fingersRemoved: null == fingersRemoved ? _self.fingersRemoved : fingersRemoved // ignore: cast_nullable_to_non_nullable
as bool,fingerMaskPath: freezed == fingerMaskPath ? _self.fingerMaskPath : fingerMaskPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _PageEdits extends PageEdits {
  const _PageEdits({this.crop, this.quarterTurns = 0, this.filter = FilterType.auto, this.brightness = 0, this.contrast = 0, this.outputAspect, final  List<PageOverlay> overlays = const <PageOverlay>[], this.photoWidthMm, this.photoHeightMm, @JsonKey(unknownEnumValue: PhotoBackground.darkBlue) this.photoBackground = PhotoBackground.original, this.backgroundMaskPath, @JsonKey(unknownEnumValue: PhotoEnhance.off) this.photoEnhance = PhotoEnhance.off, final  List<double>? faceBox, @JsonKey(defaultValue: true) this.cornersFixed = false, this.fingersRemoved = false, this.fingerMaskPath}): _overlays = overlays,_faceBox = faceBox,super._();
  factory _PageEdits.fromJson(Map<String, dynamic> json) => _$PageEditsFromJson(json);

/// null = full image.
@override final  Quad? crop;
@override@JsonKey() final  int quarterTurns;
@override@JsonKey() final  FilterType filter;
/// -100..100
@override@JsonKey() final  double brightness;
/// -100..100
@override@JsonKey() final  double contrast;
/// ID card / passport: the warp is forced to this width / height (real
/// card shape, landscape), as in the reference `warp()`. null = free.
@override final  double? outputAspect;
/// Signatures and date stamps (feature 4), drawn over the finished page.
 final  List<PageOverlay> _overlays;
/// Signatures and date stamps (feature 4), drawn over the finished page.
@override@JsonKey() List<PageOverlay> get overlays {
  if (_overlays is EqualUnmodifiableListView) return _overlays;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_overlays);
}

/// Passport photo (feature 5): the print size in millimetres.
@override final  double? photoWidthMm;
@override final  double? photoHeightMm;
/// Passport photo background: the person mask for the whole upright
/// photo (8-bit PNG, any size; sharper inside the crop, see
/// `BackgroundSegmenter.maskFor`) and the colour behind them. The
/// mask is also kept with an original background, for Enhance. Applied as
/// the crop is rendered, so every output gets it.
@override@JsonKey(unknownEnumValue: PhotoBackground.darkBlue) final  PhotoBackground photoBackground;
@override final  String? backgroundMaskPath;
/// Passport photo touch-up, before the background. Off for photos saved
/// before it existed, so they keep their look.
@override@JsonKey(unknownEnumValue: PhotoEnhance.off) final  PhotoEnhance photoEnhance;
/// Round 11b, P1-14: the face in a passport photo (ML Kit), as
/// [x0, y0, x1, y1] fractions of the upright photo, for Enhance's
/// face brightening. Null: found from the person mask instead.
 final  List<double>? _faceBox;
/// Round 11b, P1-14: the face in a passport photo (ML Kit), as
/// [x0, y0, x1, y1] fractions of the upright photo, for Enhance's
/// face brightening. Null: found from the person mask instead.
@override List<double>? get faceBox {
  final value = _faceBox;
  if (value == null) return null;
  if (_faceBox is EqualUnmodifiableListView) return _faceBox;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Round 11, P0-14: the user placed the corners in Adjust edges, so the
/// bent-page warp keeps them exactly (only the sides may bend). Pages
/// saved before it existed read as true: their corners never move.
@override@JsonKey(defaultValue: true) final  bool cornersFixed;
/// Round 11, P1-11: "Remove" was tapped for the fingers found on this
/// page; [fingerMaskPath] is their mask (8-bit PNG, the cropped and
/// turned page at any size). Applied after the filter, so a filter
/// change keeps them removed.
@override@JsonKey() final  bool fingersRemoved;
@override final  String? fingerMaskPath;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PageEdits&&(identical(other.crop, crop) || other.crop == crop)&&(identical(other.quarterTurns, quarterTurns) || other.quarterTurns == quarterTurns)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.brightness, brightness) || other.brightness == brightness)&&(identical(other.contrast, contrast) || other.contrast == contrast)&&(identical(other.outputAspect, outputAspect) || other.outputAspect == outputAspect)&&const DeepCollectionEquality().equals(other._overlays, _overlays)&&(identical(other.photoWidthMm, photoWidthMm) || other.photoWidthMm == photoWidthMm)&&(identical(other.photoHeightMm, photoHeightMm) || other.photoHeightMm == photoHeightMm)&&(identical(other.photoBackground, photoBackground) || other.photoBackground == photoBackground)&&(identical(other.backgroundMaskPath, backgroundMaskPath) || other.backgroundMaskPath == backgroundMaskPath)&&(identical(other.photoEnhance, photoEnhance) || other.photoEnhance == photoEnhance)&&const DeepCollectionEquality().equals(other._faceBox, _faceBox)&&(identical(other.cornersFixed, cornersFixed) || other.cornersFixed == cornersFixed)&&(identical(other.fingersRemoved, fingersRemoved) || other.fingersRemoved == fingersRemoved)&&(identical(other.fingerMaskPath, fingerMaskPath) || other.fingerMaskPath == fingerMaskPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,crop,quarterTurns,filter,brightness,contrast,outputAspect,const DeepCollectionEquality().hash(_overlays),photoWidthMm,photoHeightMm,photoBackground,backgroundMaskPath,photoEnhance,const DeepCollectionEquality().hash(_faceBox),cornersFixed,fingersRemoved,fingerMaskPath);

@override
String toString() {
  return 'PageEdits(crop: $crop, quarterTurns: $quarterTurns, filter: $filter, brightness: $brightness, contrast: $contrast, outputAspect: $outputAspect, overlays: $overlays, photoWidthMm: $photoWidthMm, photoHeightMm: $photoHeightMm, photoBackground: $photoBackground, backgroundMaskPath: $backgroundMaskPath, photoEnhance: $photoEnhance, faceBox: $faceBox, cornersFixed: $cornersFixed, fingersRemoved: $fingersRemoved, fingerMaskPath: $fingerMaskPath)';
}


}

/// @nodoc
abstract mixin class _$PageEditsCopyWith<$Res> implements $PageEditsCopyWith<$Res> {
  factory _$PageEditsCopyWith(_PageEdits value, $Res Function(_PageEdits) _then) = __$PageEditsCopyWithImpl;
@override @useResult
$Res call({
 Quad? crop, int quarterTurns, FilterType filter, double brightness, double contrast, double? outputAspect, List<PageOverlay> overlays, double? photoWidthMm, double? photoHeightMm,@JsonKey(unknownEnumValue: PhotoBackground.darkBlue) PhotoBackground photoBackground, String? backgroundMaskPath,@JsonKey(unknownEnumValue: PhotoEnhance.off) PhotoEnhance photoEnhance, List<double>? faceBox,@JsonKey(defaultValue: true) bool cornersFixed, bool fingersRemoved, String? fingerMaskPath
});




}
/// @nodoc
class __$PageEditsCopyWithImpl<$Res>
    implements _$PageEditsCopyWith<$Res> {
  __$PageEditsCopyWithImpl(this._self, this._then);

  final _PageEdits _self;
  final $Res Function(_PageEdits) _then;

/// Create a copy of PageEdits
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? crop = freezed,Object? quarterTurns = null,Object? filter = null,Object? brightness = null,Object? contrast = null,Object? outputAspect = freezed,Object? overlays = null,Object? photoWidthMm = freezed,Object? photoHeightMm = freezed,Object? photoBackground = null,Object? backgroundMaskPath = freezed,Object? photoEnhance = null,Object? faceBox = freezed,Object? cornersFixed = null,Object? fingersRemoved = null,Object? fingerMaskPath = freezed,}) {
  return _then(_PageEdits(
crop: freezed == crop ? _self.crop : crop // ignore: cast_nullable_to_non_nullable
as Quad?,quarterTurns: null == quarterTurns ? _self.quarterTurns : quarterTurns // ignore: cast_nullable_to_non_nullable
as int,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as FilterType,brightness: null == brightness ? _self.brightness : brightness // ignore: cast_nullable_to_non_nullable
as double,contrast: null == contrast ? _self.contrast : contrast // ignore: cast_nullable_to_non_nullable
as double,outputAspect: freezed == outputAspect ? _self.outputAspect : outputAspect // ignore: cast_nullable_to_non_nullable
as double?,overlays: null == overlays ? _self._overlays : overlays // ignore: cast_nullable_to_non_nullable
as List<PageOverlay>,photoWidthMm: freezed == photoWidthMm ? _self.photoWidthMm : photoWidthMm // ignore: cast_nullable_to_non_nullable
as double?,photoHeightMm: freezed == photoHeightMm ? _self.photoHeightMm : photoHeightMm // ignore: cast_nullable_to_non_nullable
as double?,photoBackground: null == photoBackground ? _self.photoBackground : photoBackground // ignore: cast_nullable_to_non_nullable
as PhotoBackground,backgroundMaskPath: freezed == backgroundMaskPath ? _self.backgroundMaskPath : backgroundMaskPath // ignore: cast_nullable_to_non_nullable
as String?,photoEnhance: null == photoEnhance ? _self.photoEnhance : photoEnhance // ignore: cast_nullable_to_non_nullable
as PhotoEnhance,faceBox: freezed == faceBox ? _self._faceBox : faceBox // ignore: cast_nullable_to_non_nullable
as List<double>?,cornersFixed: null == cornersFixed ? _self.cornersFixed : cornersFixed // ignore: cast_nullable_to_non_nullable
as bool,fingersRemoved: null == fingersRemoved ? _self.fingersRemoved : fingersRemoved // ignore: cast_nullable_to_non_nullable
as bool,fingerMaskPath: freezed == fingerMaskPath ? _self.fingerMaskPath : fingerMaskPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
