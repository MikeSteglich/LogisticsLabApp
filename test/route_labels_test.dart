/// Numbers of the sections of a tour on the map: all of them shown, also for short sections near nodes.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   LOGLAB_SHOTS=/tmp/shots flutter test test/route_labels_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

import 'screenshot_test.dart' show loadFonts;

void main() {
  testWidgets(
    'wandlitz: every section of the round trip has its number',
    skip: Platform.environment['LOGLAB_STDIO'] == null,
    (tester) async {
      await tester.runAsync(loadFonts);
      MapView.showTiles = false;
      SharedPreferences.setMockInitialValues({'language': 'de'});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = (await tester.runAsync(AppState.create))!;
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      state.openScenario(Scenario.parse(File('test/fixtures/wandlitz-kanten.tspx.llab').readAsStringSync()));
      state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: LogisticsLabApp(state: state),
        ),
      );
      await tester.runAsync(state.solve);
      expect(state.message, isNull);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 700));
      }
      final legs = state.connections.length;
      final labels = find.descendant(of: find.byType(MarkerLayer), matching: find.byType(Text));
      final numbers = tester.widgetList<Text>(labels).map((t) => t.data).whereType<String>().toSet();
      final shots = Platform.environment['LOGLAB_SHOTS'];
      if (shots != null) {
        await tester.runAsync(() async {
          final r = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final png = await (await r.toImage()).toByteData(format: ui.ImageByteFormat.png);
          Directory(shots).createSync(recursive: true);
          File('$shots/wandlitz-route.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      expect(numbers, containsAll([for (var k = 1; k <= legs; k++) '$k']));
      // the section back to the start goes over the crossing - no edge between Wensickendorf and Fischerstube
      final back = state.connections.firstWhere((l) => l['to'] == 'RES' || l['from'] == 'RES' && l['leg'] != 1);
      expect(back['path'], contains('KZST'));
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
    },
  );
}
