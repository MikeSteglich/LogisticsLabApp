/// Long lists: the mask stays in view, the list scrolls to the selected row (e.g. a node chosen on the map).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';
import 'package:logisticslab_app/ui/widgets.dart';

void main() {
  testWidgets('mask stays in view with long lists', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    for (var i = 0; i < 60; i++) {
      state.scenario.addNode(LatLng(52 + i / 100, 13 + i / 100), roles: ['customer']);
    }
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();
    final screen = Offset.zero & tester.view.physicalSize;
    bool visible(Finder f) => f.evaluate().isNotEmpty && screen.contains(tester.getCenter(f));

    // the last node chosen (e.g. on the map): its row comes into view, the mask is visible
    final last = state.scenario.nodes.last;
    state.selectNode(last.id);
    await tester.pumpAndSettle();
    expect(visible(find.text('${last.id} · ${last.name}')), isTrue, reason: 'title of the mask');
    expect(visible(find.text('Koordinaten suchen')), isTrue, reason: 'button in the mask');
    final row = find.descendant(of: find.byType(Section).first, matching: find.text(last.name));
    expect(visible(row.first), isTrue, reason: 'selected row scrolled into view');

    // network tab with many edges
    state.newNetwork('Direkt');
    state.addAllEdges();
    state.selectEdge(state.network!.edges.length - 1);
    await tester.pumpAndSettle();
    expect(visible(find.text('Kapazität').last), isTrue, reason: 'field of the edge mask');
  });
}
