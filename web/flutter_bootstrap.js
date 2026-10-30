{{flutter_js}}
{{flutter_build_config}}
// privacy: fonts for characters missing in the bundled Roboto from this server, not from fonts.gstatic.com (the
// default) - CanvasKit from this server too (flutter build web --no-web-resources-cdn)
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    fontFallbackBaseUrl: "fonts/fallback/"
  }
});
