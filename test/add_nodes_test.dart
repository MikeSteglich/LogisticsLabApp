/// Nodes by clicks into the map - for every problem, also without roles (tsp).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('every click into the map adds a node until the mode is ended', (tester) async {
    MapView.showTiles = false;
    AppState.reverseGeocoding = false; // no core in this test
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    final before = state.scenario.nodes.length;

    // tpp: the new nodes are customers
    await tester.tap(find.text('Knoten setzen'));
    await tester.pump();
    expect(state.addingNodes, isTrue);
    expect(find.text('In die Karte klicken – jeder Klick legt einen Knoten an'), findsOneWidget);
    state.tapMap(const LatLng(52.6, 13.1));
    state.tapMap(const LatLng(52.0, 13.9));
    await tester.pump();
    expect(state.scenario.nodes.length, before + 2);
    expect(state.node!.roles, ['customer']);
    expect(state.node!.position.latitude, closeTo(52.0, 1e-9));
    expect(state.addingNodes, isTrue); // the mode stays
    expect(state.clickedGeometry, state.geometry); // the map keeps its section

    // tsp: no roles
    state.newProblem('tsp');
    state.tapMap(const LatLng(52.2, 13.5));
    expect(state.node!.roles, isEmpty);

    // ended with the cross
    await tester.pump();
    await tester.tap(find.byTooltip('Abbrechen'));
    await tester.pump();
    expect(state.addingNodes, isFalse);
    final count = state.scenario.nodes.length;
    state.tapMap(const LatLng(52.3, 13.3));
    expect(state.scenario.nodes.length, count);
  });

  testWidgets('the address of a node set on the map', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    const p = LatLng(52.2999, 13.2597); // Ludwigsfelde
    state.addNode(p);
    final id = state.selectedNode!;
    await tester.runAsync(() => state.addressOf(id, p));
    final n = state.scenario.node(id)!;
    // needs the geo service of OSM - without an answer the address stays empty
    if ((n.address ?? '').isNotEmpty) {
      expect(n.address, contains('Ludwigsfelde'));
      expect((n.json['addressDetails'] as Map)['city'], 'Ludwigsfelde');
    }
    // an address typed meanwhile is kept
    state.edit(() => n.address = 'Werkstraße 1');
    await tester.runAsync(() => state.addressOf(id, p));
    expect(n.address, 'Werkstraße 1');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
