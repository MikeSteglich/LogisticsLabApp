/// Every problem type checks its data before solving: an empty scenario or nodes without their values give a
/// clear message of the app - the core is not asked.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';

void main() {
  testWidgets('empty scenario: every problem type refuses with a message', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    for (final type in modules.keys) {
      state.openScenario(Scenario.empty());
      state.newProblem(type);
      await tester.runAsync(state.solve);
      expect(state.lastResult, 'error', reason: type);
      expect(state.message, isNotEmpty, reason: type);
      expect(state.solving, isFalse, reason: type);
    }
  });

  testWidgets('nodes without supply and demand: every problem with quantities refuses', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.edit(() {
      for (final n in state.scenario.nodes) {
        for (final k in ['supply', 'demand', 'supplies', 'demands']) {
          n.json.remove(k);
        }
      }
    });
    for (final p in state.scenario.problems) {
      final spec = modules[p.type];
      if (spec == null || spec.type == 'tsp') continue; // a tour needs no quantities
      state.chooseProblem(p.name);
      expect(state.nodeProblems, isNotEmpty, reason: p.name);
      expect(state.nodeProblems.join(), anyOf(contains('Angebot'), contains('Nachfrage')), reason: p.name);
    }
    // costs as the measure without cost rates
    state.chooseProblem('Transport direkt vom Werk');
    state.edit(
      () => state.scenario.matrix
        ..remove('costPerKm')
        ..remove('costPerHour'),
    );
    expect(state.nodeProblems, contains(startsWith('Bewertung nach Kosten')));
  });
}
