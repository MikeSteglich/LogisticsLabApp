/// TPP with maximisation of the contribution: price of the customer - unit cost of the supplier - transport costs.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/tpp_max_test.dart
///
/// Without LOGLAB_STDIO the part with the solver is skipped.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/tpp.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no network needed
  state.chooseProblem('Transport direkt vom Werk');
  return state;
}

void main() {
  testWidgets('price and unit cost only with maximisation', (tester) async {
    final state = await _state(tester);
    final spec = tppSpec;
    bool visible(String role, String key) => spec.roles
        .firstWhere((r) => r.defaultRole == role)
        .nodeFields
        .firstWhere((f) => f.key == key)
        .isVisible(state.problem!.parameters);
    expect(visible('customer', 'price'), isFalse);
    state.edit(() => state.problem!.parameters['objSense'] = 'max');
    expect(visible('customer', 'price'), isTrue);
    expect(visible('supplier', 'unitCost'), isTrue);
    expect(spec.objective!(state.problem!.parameters), 'netContribution');
  });

  testWidgets('contribution maximised', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    // demand ranges: Cottbus is not worth it with its low price
    state.edit(() {
      state.problem!.parameters
        ..['objSense'] = 'max'
        ..['useDemandRanges'] = true;
      for (final n in state.scenario.nodes) {
        if (n['id'] == 'W') n['unitCost'] = 20;
        final price = {'B': 80, 'P': 70, 'F': 75, 'C': 22}[n['id']];
        if (price != null) {
          n['price'] = price;
          n['minDemand'] = 0;
          n['maxDemand'] = 100;
        }
      }
    });
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    final summary = state.solution!.results!['summary'] as Map;
    expect(summary['netContribution'], greaterThan(0));
    expect(state.ratesAreContributions, isTrue);
    expect(state.rateLabels.$1, 'Deckungsbeitrag je Einheit');
    expect(state.connections.every((c) => (c['rate'] as num) > 0), isTrue);
    expect(state.connections.map((c) => c['to']), isNot(contains('C')));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
