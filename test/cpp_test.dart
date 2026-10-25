/// Chinese postman: every edge of the network from the start and back - directed edges one way.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/cpp_test.dart
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
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  return state;
}

void main() {
  testWidgets('cpp: network and start required, each edge directed or not', (tester) async {
    final state = await _state(tester);
    state.newProblem('cpp');
    expect(state.spec!.edgeDirections, isTrue);
    expect(state.isTransport, isFalse);
    expect(state.nodeProblems, isEmpty); // the start is checked with the parameters
    expect(state.spec!.validateParameters(state.problem!.parameters), isNotEmpty);
  });

  testWidgets('cpp solved: every edge, the dead ends twice', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.newProblem('cpp');
    state.chooseNetwork('supply');
    state.edit(() {
      state.network!.directed = false;
      state.problem!.parameters['startNode'] = 'W';
    });
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    final legs = state.connections;
    expect(legs.first['from'], 'W');
    expect(legs.last['to'], 'W');
    // every edge in the tour
    for (final e in state.network!.edges) {
      expect(
        legs.any((l) => (l['from'] == e.from && l['to'] == e.to) || (l['from'] == e.to && l['to'] == e.from)),
        isTrue,
        reason: '${e.from}-${e.to}',
      );
    }
    final summary = state.solution!.results!['summary'] as Map;
    expect(summary['nrOfRepeats'], 3); // Cottbus, Frankfurt, Potsdam: dead ends
    // the sections over the dead ends: traversed twice - pass 1/2 and 2/2
    final repeated = legs.where((l) => l['passes'] != null).toList();
    expect(repeated.length, 6);
    final toCottbus = repeated.where((l) => l['from'] == 'C' || l['to'] == 'C').toList();
    expect([for (final l in toCottbus) '${l['pass']}/${l['passes']}'], ['1/2', '2/2']);
    expect(legs.where((l) => l['from'] == 'W' && l['passes'] != null), isEmpty);
    expect(summary['tourLength'], closeTo((summary['edgesLength'] as num) + (summary['extraLength'] as num), 1e-6));

    // directed edges without a way back: refused with a message
    state.edit(() => state.network!.directed = true);
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'error');
    expect(state.message, contains('back to the start'));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
