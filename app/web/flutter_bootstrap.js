{{flutter_js}}
{{flutter_build_config}}

// Load CanvasKit from this app's own build instead of Google's CDN, so the
// app works on networks that block or slow down gstatic.com.
_flutter.loader.load({
  config: { canvasKitBaseUrl: "canvaskit/" },
});
