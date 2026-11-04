# ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
# Keep Flutter plugin registrant
-keep class io.flutter.plugins.** { *; }

# google_mlkit_text_recognition references every script's options class, but
# only the Latin model is bundled. Tell R8 the others are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
