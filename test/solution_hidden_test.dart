/// A solution is not shown once nodes or edges have been added, deleted or switched off - it would not fit them;
/// other changes leave it shown as stale.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('edges changed: the solution is hidden', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    final s = Scenario.empty();
    s.matrix['matrixSource'] = 'beeline';
    s.addNode(const LatLng(52.3, 13.6), roles: ['supplier'])['supply'] = 100;
    s.addNode(const LatLng(52.4, 13.5), roles: ['transit']);
    s.addNode(const LatLng(52.5, 13.4), roles: ['customer'])['demand'] = 80;
    final net = s.addNetwork('Netz', directed: false);
    net.addEdge('N1', 'N2');
    net.addEdge('N2', 'N3');
    net.addEdge('N1', 'N3');
    s.addProblem('mincostflow', 'Fluss', {}).network = 'Netz';
    state.openScenario(s);
    await tester.runAsync(state.solve);
    expect(state.solution!.status, 'solution');

    // a value changed: shown as stale
    state.edit(() => state.scenario.node('N3')!['demand'] = 70);
    expect(state.solution, isNotNull);
    expect(state.solutionIsStale, isTrue);
    expect(state.solutionHidden, isFalse);

    // an edge deleted: hidden - back again: shown
    final edges = state.scenario.json['networks']['Netz']['edges'] as List;
    final removed = edges.removeAt(2);
    state.edit(() {});
    expect(state.solution, isNull);
    expect(state.solutionHidden, isTrue);
    expect(state.connections, isEmpty);
    edges.add(removed);
    state.edit(() {});
    expect(state.solution, isNotNull);

    // a node switched off: hidden
    state.edit(() => state.scenario.node('N2')!.active = false);
    expect(state.solutionHidden, isTrue);
  });

  testWidgets('a tap on a table header: no highlight on the map', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.selectFlow(2);
    expect(state.selectedFlow, 2);
    state.clearHighlights();
    expect(state.selectedFlow, isNull);
    state.highlightNode('N1');
    state.selectRoute(1);
    state.clearHighlights();
    expect([state.highlightedNode, state.selectedRoute, state.selectedEdge], [null, null, null]);
  });
}
