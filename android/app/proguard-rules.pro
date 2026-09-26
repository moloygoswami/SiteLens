# SiteLens: preserve Flutter generated plugin registrant
# invoked reflectively by Flutter embedding.
-keep class io.flutter.plugins.GeneratedPluginRegistrant {
    public static void registerWith(io.flutter.embedding.engine.FlutterEngine);
    public <init>();
}
