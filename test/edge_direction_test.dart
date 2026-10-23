/// Edges of transport problems: suppliers -> transshipment nodes -> customers, against the direction turned round.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/scenario.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  return state;
}

void main() {
  testWidgets('network flow: all connections over the transshipment nodes', (tester) async {
    final state = await _state(tester);
    state.newProblem('mincostflow');
    state.newNetwork('neu');
    expect(state.transitCandidates, ['D1', 'D2']);
    // plant -> 2 warehouses, warehouses -> 4 customers
    expect(state.addAllEdges(), 2 + 2 * 4);
    final edges = state.network!.edges.map((e) => '${e.from}-${e.to}').toList();
    expect(edges, containsAll(['W-D1', 'W-D2', 'D1-B', 'D2-C']));
    expect(edges, isNot(contains('W-B')));
    expect(state.network!.directed, isTrue);

    // into a supplier or out of a customer: not allowed, against the direction: turned round
    expect(state.edgeProblem('B', 'P'), 'ui.edge.direction');
    expect(state.addEdge('B', 'P'), isFalse);
    expect(state.edgeAllowed('D1', 'D2'), isTrue); // transshipment nodes among each other
    expect(state.addEdge('D2', 'D1'), isTrue);
    state.network!.removeEdgeAt(state.network!.edges.length - 1);
  });

  testWidgets('tpp: only suppliers -> customers, directed also in an undirected network', (tester) async {
    final state = await _state(tester);
    state.chooseProblem('Transport direkt vom Werk');
    state.newNetwork('ungerichtet', directed: false);
    expect(state.addEdge('B', 'W'), isTrue); // turned round
    final e = state.network!.edges.single;
    expect('${e.from}-${e.to}', 'W-B');
    expect(e['directed'], isTrue);
    expect(state.edgeAllowed('W', 'D1'), isFalse); // D1 is no customer of the tpp
  });
}
