/// Shortest path from a start to an end node in the network.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/shortest_path_test.dart
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
  state.openScenario(Scenario.parse(File('test/fixtures/wandlitz-kuerzester-weg.nwfx.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  return state;
}

void main() {
  testWidgets('start and end in the parameters, edges in both directions allowed', (tester) async {
    final state = await _state(tester);
    state.newProblem('shortestpath');
    final keys = state.spec!.visibleParameters(state.problem!.parameters).map((f) => f.key);
    expect(keys, containsAll(['startNode', 'endNode']));
    expect(state.isTransport, isFalse); // the edges keep their direction
    expect(state.spec!.edgeDirections, isTrue);
  });

  testWidgets('shortest path Basdorf -> Zehlendorf and back', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.newProblem('shortestpath');
    state.chooseNetwork('network');
    Future<List<Map<String, dynamic>>> solve(String from, String to) async {
      state.edit(
        () => state.problem!.parameters
          ..['startNode'] = from
          ..['endNode'] = to,
      );
      await tester.runAsync(state.solve);
      return state.connections;
    }

    var legs = await solve('BA', 'ZE');
    expect(state.message, isNull);
    expect(state.isRoute, isTrue);
    expect(state.analysis, isNull); // a way has no quantities of the nodes
    expect(legs.first['from'], 'BA');
    expect(legs.last['to'], 'ZE');
    final length = legs.fold<num>(0, (sum, l) => sum + (l['value'] as num));
    expect(state.solution!.results!['summary']['pathLength'], closeTo(length, 1e-6));

    legs = await solve('ZE', 'BA');
    expect(legs.first['from'], 'ZE');
    expect(legs.last['to'], 'BA');

    // no way at all: a node that is no part of a way back
    state.edit(() {
      for (final e in state.network!.edges.where((e) => e.from == 'BA' || e.to == 'BA')) {
        e['directed'] = true;
        if (e.to == 'BA') {
          final from = e.from;
          e.from = 'BA';
          e.to = from; // only away from Basdorf
        }
      }
    });
    await solve('ZE', 'BA');
    expect(state.lastResult, 'error');
    expect(state.message, contains('no way'));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
