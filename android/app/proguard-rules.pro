# Keep the generated Flutter plugin registrant used to wire Android plugins.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep background execution and notification plugin classes that are invoked
# outside the normal activity startup path.
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ──────────────────────────────────────────────────────────────────────
# Gson / TypeToken — CRITICAL for flutter_local_notifications
#
# The plugin uses Gson internally to serialize/deserialize scheduled
# notification payloads into Android SharedPreferences. Gson creates
# anonymous TypeToken subclasses at runtime via reflection, and needs:
#   1. The TypeToken class itself with all members preserved.
#   2. Every subclass of TypeToken with members AND generic signature.
#   3. The Signature attribute so Java reflection can read generic
#      type parameters (e.g. TypeToken<List<ScheduledNotification>>).
#   4. Annotation attributes used by Gson for field mapping.
#
# Without these, R8 strips the generic metadata and Gson throws:
#   "TypeToken must be created with a type argument: new TypeToken<...>() {}"
#
# The previous rule was missing { *; } on the subclass keep, so R8 kept
# the class names but stripped their fields/methods/signatures.
# ──────────────────────────────────────────────────────────────────────
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }

# Keep Gson internals that perform reflective field access on models.
-keep class com.google.gson.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep generic signatures and annotations that R8 would otherwise strip.
# Signature: required for Gson TypeToken generic resolution.
# Annotation: required for Gson @SerializedName and similar metadata.
# EnclosingMethod/InnerClasses: required for anonymous TypeToken subclasses.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
