/// Editing while solving: the solver gets the data of the start, the solution is marked stale afterwards.
///
/// Runs only with LOGLAB_STDIO (local solver, see screenshot_test.dart).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('edit while solving', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';

    await tester.runAsync(() async {
      final solving = state.solve(); // starts the solver first - the data are taken before
      state.selectNode('B');
      state.edit(() => state.node!['demand'] = 1000); // more than the supply of 100 - infeasible if solved
      await solving;
    });
    expect(state.lastResult, 'solution'); // solved with the demand of 40
    final flows = state.solution!.results!['assignments'] as List;
    expect(flows.firstWhere((a) => a['to'] == 'B')['flow'], 40);
    expect(state.solutionIsStale, isTrue); // the data have changed since

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
