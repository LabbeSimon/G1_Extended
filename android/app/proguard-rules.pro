#Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

-keep class com.builttoroam.devicecalendar.** { *; }
-keep class com.google.android.play.core.**  { *; }


# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Vosk speech recognition (JNA required)
-keep class com.sun.jna.* { *; }
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }

# JNA references Java AWT classes that don't exist on Android - ignore them
-dontwarn java.awt.**
-dontwarn com.sun.jna.Native$AWT
-dontwarn com.sun.jna.platform.win32.**
-dontwarn com.sun.jna.platform.unix.**

# androidx.window declares the OEM window extensions as compile-only: they
# exist at runtime only on devices whose manufacturer ships them, so R8 is
# right that they are absent and wrong to treat it as fatal. Pulled in
# transitively by vosk_flutter.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# flutter_local_notifications deserialises its scheduled notifications through
# Gson, so R8 cannot see the constructors it uses. Stripping them breaks
# reminders in release builds only, which is a miserable thing to debug.
-keep class com.dexterous.** { *; }
