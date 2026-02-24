# Moshi
-keep class dev.tuist.app.data.model.** { *; }
-keep class dev.tuist.app.api.model.** { *; }

# Retrofit
-keepattributes Signature
-keepattributes *Annotation*

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Google Tink (used by EncryptedSharedPreferences)
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi
