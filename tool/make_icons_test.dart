/// Writes the app icons from the logo (lib/ui/logo.dart) - run after changing the logo:
///
///   flutter test tool/make_icons_test.dart && python3 tool/make_ico.py
///
/// macOS: AppIcon.appiconset (with the margin of macOS icons), web: icons and favicon, Windows: PNGs for the .ico
/// (tool/make_ico.py builds windows/runner/resources/app_icon.ico from them), Linux: assets/icon/app_icon.png.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:logisticslab_app/ui/logo.dart';

Future<void> _png(String path, int size, {double margin = 0}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  LogoPainter(margin: margin).paint(canvas, ui.Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('app icons', () async {
    // macOS: the tile is 824 of 1024 points (Big Sur grid)
    for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
      await _png('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png', s, margin: 100 / 1024);
    }
    await _png('web/favicon.png', 32);
    await _png('web/icons/Icon-192.png', 192);
    await _png('web/icons/Icon-512.png', 512);
    await _png('web/icons/Icon-maskable-192.png', 192, margin: 0.1);
    await _png('web/icons/Icon-maskable-512.png', 512, margin: 0.1);
    for (final s in [16, 24, 32, 48, 64, 128, 256]) {
      await _png('build/icons/windows/icon_$s.png', s, margin: 0.03);
    }
    await _png('assets/icon/app_icon.png', 256, margin: 0.03);
    await _png('build/icons/logo_preview.png', 512, margin: 100 / 1024);
  });
}
