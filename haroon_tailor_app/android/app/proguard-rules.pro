# Flutter and SharedPreferences ProGuard/R8 Rules
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar { *; }
-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesAsyncApiRegistrar { *; }

-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
