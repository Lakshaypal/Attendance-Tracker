# The ML Kit text-recognition plugin can construct a recogniser for Latin,
# Chinese, Devanagari, Japanese or Korean script, and references all five.
# This app only ever asks for Latin (see lib/src/scan/ocr_service.dart), so the
# other four artifacts are deliberately not bundled — keeping them out saves
# tens of megabytes. R8 only needs to be told that their absence is intended.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
