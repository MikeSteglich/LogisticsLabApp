/// Labels of the map without overlaps: dense nodes get fewer labels, more after zooming in, none with the layer off.
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

void main() {
  testWidgets('labels without overlaps', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    // 40 customers close to Berlin
    for (var i = 0; i < 40; i++) {
      state.scenario.addNode(LatLng(52.50 + (i % 8) * 0.004, 13.38 + (i ~/ 8) * 0.006), roles: ['customer']);
    }
    state.selectNode(state.scenario.nodes[30].id); // one of the dense nodes
    await tester.pumpWidget(LogisticsLabApp(state: state));
    state.geometry++; // the map shows all nodes
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final names = {for (final n in state.scenario.nodes) n.name};
    List<Rect> labels() => [
      for (final e in find.descendant(of: find.byType(MarkerLayer), matching: find.byType(Text)).evaluate())
        if (names.contains((e.widget as Text).data)) tester.getRect(find.byWidget(e.widget)),
    ];
    final few = labels();
    expect(few.length, lessThan(names.length)); // not all names fit
    for (var i = 0; i < few.length; i++) {
      for (var j = i + 1; j < few.length; j++) {
        expect(few[i].deflate(2).overlaps(few[j].deflate(2)), isFalse, reason: 'labels $i and $j overlap');
      }
    }
    final selected = state.node!.name;
    expect(
      find.descendant(of: find.byType(MarkerLayer), matching: find.text(selected)),
      findsOneWidget,
      reason: 'the selected node has its label',
    );

    // zoom in: more labels
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    map.move(state.node!.position, map.camera.zoom + 4);
    await tester.pumpAndSettle();
    final zoomed = labels();
    expect(zoomed.length, greaterThan(few.length));

    // layer off: no labels
    // the layers are a small button - they open on a click
    expect(find.text('Beschriftung'), findsNothing);
    await tester.tap(find.byTooltip('Ebenen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beschriftung'));
    await tester.pumpAndSettle();
    expect(labels(), isEmpty);
    // a click on the map closes them
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)) + const Offset(-200, 150));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Beschriftung'), findsNothing);
  });
}
