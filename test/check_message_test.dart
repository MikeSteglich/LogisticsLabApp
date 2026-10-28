/// The message of the checks before solving follows the data: it goes once the missing value is entered.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('costs without a cost rate: the message goes with the rate', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.chooseProblem(state.scenario.problems.first.name);
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.edit(() => state.problem!.parameters['matrixMode'] = 'costs');
    state.scenario.matrix.remove('costPerKm');
    state.scenario.matrix.remove('costPerHour');
    await tester.runAsync(state.solve);
    expect(state.message, contains('Kosten je km oder je Stunde'));
    expect(state.lastResult, 'error');
    // another edit, still without a rate: the message stays
    state.edit(() => state.scenario.matrix['matrixSource'] = 'beeline');
    expect(state.message, contains('Kosten je km oder je Stunde'));
    state.edit(() => state.scenario.matrix['costPerKm'] = 0.2);
    expect(state.message, isNull);
    expect(state.lastResult, isNull);
  });

  testWidgets('a network flow: a supplier with the throughput 0 refused before solving', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.chooseProblem('Distribution über die Lager');
    expect(state.nodeProblems, isEmpty);
    final supplier = state.scenario.nodes.firstWhere((n) => n.roles.contains('supplier'));
    state.edit(() => supplier['maxCap'] = 0);
    expect(state.nodeProblems.single, contains('Höchstdurchsatz 0 bei ${supplier.name}'));
  });
}
