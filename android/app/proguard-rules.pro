# Keep the generated Flutter plugin registrant used to wire Android plugins.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep background execution and notification plugin classes that are invoked
# outside the normal activity startup path.
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
