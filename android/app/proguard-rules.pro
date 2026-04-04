# Keep the generated Flutter plugin registrant used to wire Android plugins.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep background execution and notification plugin classes that are invoked
# outside the normal activity startup path.
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson / TypeToken — preserve generic signatures so that Gson (used internally
# by flutter_local_notifications to serialize scheduled notification data) can
# reflectively create TypeToken instances at runtime.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep generic signatures and annotations that R8 would otherwise strip.
-keepattributes Signature
-keepattributes *Annotation*
