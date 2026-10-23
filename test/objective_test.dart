/// Solution tab: the value of the objective function is highlighted, values in the unit of the solution.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  Future<AppState> show(WidgetTester tester, {String objSense = 'min', String? valueUnit}) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.problem!.parameters['objSense'] = objSense;
    state.solutions[state.problemName!] = SolutionState({
      'status': 'solution',
      'valueUnit': ?valueUnit,
      'results': {
        'objVal': 1234.5,
        'summary': {'totalCosts': 1234.5, 'totalFlow': 100, 'minCostRate': 10, 'maxCostRate': 42},
        'assignments': [
          {'from': 'W', 'to': 'B', 'flow': 40, 'rate': 1},
        ],
      },
    }, state.revision);
    state.setTab(DataTab.solution);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  /// label of the card marked as objective
  String marked(WidgetTester tester) {
    final badge = find.text('Zielfunktion');
    expect(badge, findsOneWidget);
    // the note lies on the edge of the card - both in one Stack, the first text is the label
    final card = find.ancestor(of: badge, matching: find.byType(Stack));
    final texts = find.descendant(of: card.first, matching: find.byType(Text));
    return (tester.widgetList<Text>(texts).first).data!;
  }

  testWidgets('minimise costs: total costs', (tester) async {
    addTearDown(tester.view.reset);
    await show(tester);
    expect(marked(tester), 'Gesamtkosten');
    expect(find.text('1.234,50 €'), findsOneWidget);
  });

  testWidgets('minimax: largest cost rate', (tester) async {
    addTearDown(tester.view.reset);
    await show(tester, objSense: 'minimax');
    expect(marked(tester), 'Größter Kostensatz');
  });

  testWidgets('distances: values in km', (tester) async {
    addTearDown(tester.view.reset);
    await show(tester, valueUnit: 'km');
    expect(find.text('1.234,5 km'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
  });
}
