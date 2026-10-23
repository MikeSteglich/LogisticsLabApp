/// Network of a problem: create it, all connections, edge mask, drawing on the map, solving with the edge values.
///
/// The solving part runs only with LOGLAB_STDIO (local solver, see screenshot_test.dart).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('network and edges', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(
      Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()),
      name: 'brandenburg.llab',
    );
    // straight lines: the map loads no roads (a solver started from the fake time of testWidgets would never get
    // ready), the solving needs no network
    state.scenario.matrix['matrixSource'] = 'beeline';
    await tester.pumpWidget(LogisticsLabApp(state: state));
    expect(state.problem!.type, 'tpp');
    expect(state.problem!.network, isNull);

    // new network of the problem
    state.newNetwork('Direkt');
    await tester.pump();
    expect(state.problem!.network, 'Direkt');
    expect(state.tab, DataTab.network);
    expect(find.text('Noch keine Kanten'), findsOneWidget);

    // all connections suppliers -> customers: W -> B, P, F, C
    await tester.tap(find.text('Alle Verbindungen anlegen'));
    await tester.pump();
    expect([for (final e in state.network!.edges) '${e.from}-${e.to}'], ['W-B', 'W-P', 'W-F', 'W-C']);
    expect(find.text('4 Kanten angelegt'), findsOneWidget);
    await tester.tap(find.text('Alle Verbindungen anlegen'));
    await tester.pump();
    expect(state.network!.edges.length, 4); // nothing new

    // edge mask: capacity is kept, but used only with the parameter - switched on from the hint
    state.selectEdge(0);
    await tester.pump();
    state.edit(() => state.edge!['capacity'] = 40);
    state.edit(() => state.edge!['fixedCost'] = 10);
    await tester.pump();
    expect(find.textContaining('Wird erst genutzt'), findsNWidgets(2));
    await tester.tap(find.text('Einschalten').first);
    await tester.pump();
    expect(state.problem!.parameters['useCapacities'], isTrue);
    await tester.tap(find.text('Einschalten').first);
    await tester.pump();
    expect(state.problem!.parameters['useFixedCosts'], isTrue);
    expect(find.textContaining('Wird erst genutzt'), findsNothing);

    // drawing on the map: start node, end node
    state.selectEdge(3); // W -> C, drawn again
    state.deleteEdge();
    state.setDrawingEdge(true);
    state.tapNode('C');
    expect(state.edgeStart, 'C');
    state.tapNode('W');
    await tester.pump();
    expect(state.drawingEdge, isFalse);
    // drawn against the direction of the tpp: turned round
    expect(state.edge!.from, 'W');
    expect(state.edge!.to, 'C');
    // a tpp has no edges to warehouses
    state.setDrawingEdge(true);
    state.tapNode('W');
    expect(state.tapNode('D1'), 'ui.edge.direction');
    expect(state.addEdge('W', 'B'), isFalse); // exists

    // deleting a node removes its edges - the scenario stays valid
    expect(state.network!.edges.length, 4);
    // D1 is also the depot of the vehicle and the start of the tsp - these references are removed too
    expect(state.scenario.usages('D1').map((u) => u.$1), containsAll(['ui.use.edges', 'ui.use.depot', 'ui.use.param']));
    state.selectNode('D1');
    state.deleteNode();
    await tester.pump();
    expect([for (final e in state.network!.edges) '${e.from}-${e.to}'], ['W-B', 'W-P', 'W-F', 'W-C']);
    expect(state.scenario.usages('D1'), isEmpty);
    expect(state.scenario.problem('Rundreise')!.parameters.containsKey('startNode'), isFalse);

    if (Platform.environment['LOGLAB_STDIO'] == null) return;
    // the core gets the network: fixed costs of W -> B, capacity 40 of W -> B (demand of Berlin)
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    await tester.runAsync(state.solve);
    await tester.pump();
    expect(state.message, isNull);
    final res = state.solution!.results!;
    expect(state.solution!.status, 'solution');
    expect((res['summary'] as Map)['totalFixedCosts'], 10);
    final wb = (res['assignments'] as List).firstWhere((a) => a['from'] == 'W' && a['to'] == 'B');
    expect(wb['flow'], lessThanOrEqualTo(40));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
