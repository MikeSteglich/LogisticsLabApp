/// The map shows all nodes after opening a file and after changes of the nodes or their coordinates.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

/// rebuild (the map schedules the fit), let the pause of the fit pass, rebuild with the new camera
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('map shows all nodes', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    LatLngBounds visible() => tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera.visibleBounds;
    void expectAllVisible(String when) {
      final b = visible();
      for (final n in state.scenario.nodes) {
        expect(b.contains(n.position), isTrue, reason: '$when: ${n.id} ${n.position} not in $b');
      }
    }

    // open a file
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()),
        name: 'brandenburg.llab');
    await settle(tester);
    expectAllVisible('open');
    final zoomOpen = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera.zoom;

    // coordinates of a node changed: far to the south (Dresden)
    state.selectNode('C');
    state.edit(() => state.node!.position = const LatLng(51.05, 13.74));
    await settle(tester);
    expectAllVisible('moved');
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera.zoom, lessThan(zoomOpen));

    // new node in Hamburg
    state.addNode(const LatLng(53.55, 9.99));
    await settle(tester);
    expectAllVisible('added');
  });
}
