/// TSP with a network: the shortest paths through it by default - only over its edges a node with one neighbour
/// makes a round trip impossible, the app says so before solving.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';

void main() {
  testWidgets('a node with one edge only blocks a tour over the edges', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.newProblem('tsp');
    final ids = [
      for (final n in state.scenario.nodes)
        if (n.active) n.id,
    ];
    final name = state.scenario.node(ids.last)!.name;
    state.newNetwork('Netz', directed: false);
    state.chooseNetwork('Netz');
    // a ring through all nodes but the last one - it hangs on the first
    state.edit(() {
      final net = state.network!;
      for (var i = 0; i < ids.length - 1; i++) {
        net.addEdge(ids[i], ids[(i + 1) % (ids.length - 1)]);
      }
      net.addEdge(ids.last, ids.first);
    });
    expect(state.spec!.networkFields, [networkModeField]);
    // the shortest paths (default): no message
    expect(state.nodeProblems, isEmpty);
    state.edit(() => state.problem!.json['networkMode'] = 'edges');
    expect(state.nodeProblems, [contains('Nur eine Kante bei $name')]);
    // a passage ending there or an open end: possible
    state.edit(
      () => state.problem!.parameters.addAll({'tourType': 'path', 'startNode': ids.first, 'endNode': ids.last}),
    );
    expect(state.nodeProblems, isEmpty);
    state.edit(() => state.problem!.parameters['tourType'] = 'open');
    expect(state.nodeProblems, isEmpty);
  });
}
