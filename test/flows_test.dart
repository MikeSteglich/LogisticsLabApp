/// Network flows with the local solver: min cost flow, max flow, multi-commodity, multimodal, multi-stage WLP.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/flows_test.dart
///
/// Without LOGLAB_STDIO the part with the solver is skipped.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no network needed
  return state;
}

void main() {
  testWidgets('checks of the app before solving', (tester) async {
    final state = await _state(tester);
    // a new max flow: no network, no source and sink
    state.newProblem('maxflow');
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'error');
    expect(state.message, contains('braucht ein Netz'));
    expect(state.message, contains('Quelle fehlt'));
    expect(state.solving, isFalse);
  });

  testWidgets('all network flows solved', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    Future<void> solve(String problem) async {
      state.chooseProblem(problem);
      await tester.runAsync(state.solve);
      expect(state.message, isNull, reason: problem);
      expect(state.lastResult, 'solution', reason: problem);
    }

    // min cost flow with fixed costs of the edges: flows along the edges, cost rates
    await solve('Distribution über die Lager');
    expect(state.connections.map((c) => '${c['from']}-${c['to']}'), contains('W-D1'));
    expect(state.connections.first['rate'], isNotNull);
    expect(state.analysis!.missing('customer'), 0);
    // utilization of the edge capacities, the warehouses as transshipment nodes in the node list
    final wd1Edge = state.connections.firstWhere((c) => c['from'] == 'W' && c['to'] == 'D1');
    expect(wd1Edge['utilization'], closeTo((wd1Edge['flow'] as num) / (wd1Edge['capacity'] as num), 1e-9));
    final through = state.analysis!.through.map((u) => u.node.id).toSet();
    expect(through, containsAll(['D1', 'D2']));
    expect(state.analysis!.use('D1')!.actual, greaterThan(0));
    expect(state.nodesOf(AppState.transitFilter).map((n) => n.id), containsAll(['D1', 'D2']));
    expect(state.nodesOf('').map((n) => n.id), isNot(contains('D1')));

    // multi-commodity: split per commodity
    await solve('Zwei Güter');
    expect(state.split(state.connections.first), allOf(contains('Lebensmittel'), contains('Pakete')));

    // multimodal: split per mode - the train between the plant and Wildau
    await solve('Lkw oder Bahn');
    final wd1 = state.connections.firstWhere((c) => c['from'] == 'W' && c['to'] == 'D1');
    expect(state.split(wd1), contains('Bahn'));

    // multi-stage WLP: open warehouses
    await solve('Lager mehrstufig');
    expect(state.openNodes, {'D1': true, 'D2': true});
    expect(state.analysis!.use('D1')!.role, 'candidate');
    expect(state.analysis!.use('D1')!.utilization, isNotNull);

    // max flow from the plant to Berlin over the network supply
    state.newProblem('maxflow');
    state.chooseNetwork('supply');
    state.edit(
      () => state.problem!.parameters
        ..['source'] = 'W'
        ..['sink'] = 'B',
    );
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    expect(state.solution!.results!['objVal'], 140);

    // max flow from all suppliers to all customers: artificial source and sink, limited by the supply of the plant
    state.edit(() => state.problem!.parameters['endpoints'] = 'roles');
    expect(state.problemRoles, ['supplier', 'customer']);
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    expect(state.solution!.results!['objVal'], 100);
    expect(state.analysis!.use('W')!.actual, 100);
    expect(state.analysis!.missing('customer'), 0);
    expect(state.connections.where((c) => c['from'] == 'W').map((c) => c['flow'] as num).reduce((a, b) => a + b), 100);

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
