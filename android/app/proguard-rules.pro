# ============================================================
# ProGuard / R8 rules — ZEGOCLOUD (zego_uikit_prebuilt_call,
# zego_express_engine, zego_zim, zego_zpns).
# Zinatumika tu R8/minify ikiwashwa; sasa minify haijawashwa.
# ============================================================
-keep class com.zegocloud.** { *; }
-keep class im.zego.** { *; }
-keep class com.zego.** { *; }
-keep class tv.danmaku.** { *; }

-dontwarn com.zegocloud.**
-dontwarn im.zego.**
-dontwarn com.zego.**

# JNI bindings za Express Engine
-keepclasseswithmembers class * {
    native <methods>;
}
-keep class im.zego.zego_express_engine.** { *; }
-keep class im.zego.zim.** { *; }
-keep class im.zego.zpns.** { *; }

# flutter_callkit_incoming (dependency ya ZEGO callkit)
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class androidx.core.app.** { *; }