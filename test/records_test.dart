/// Commodities and modes of the scenario: add and delete in the parameters tab.
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
  testWidgets('commodities added and deleted', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    state.chooseProblem('Zwei Güter');
    state.setTab(DataTab.parameters);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    final add = find.widgetWithText(OutlinedButton, 'Gut');
    await tester.scrollUntilVisible(add, 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(add);
    await tester.pump();
    expect(state.scenario.commodities.length, 3);
    final delete = find.byTooltip('Löschen');
    final list = find.ancestor(of: add, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(delete.last, 100, scrollable: list);
    await tester.drag(list, const Offset(0, -150));
    await tester.pump();
    await tester.tap(delete.last);
    await tester.pump();
    expect(state.scenario.commodities.length, 2);

    // a deleted commodity leaves no values at the nodes and edges
    bool refersTo(String id) => state.scenario.nodes.any(
      (n) => ['supplies', 'demands', 'capacityFactors'].any((k) => (n[k] as Map?)?.containsKey(id) ?? false),
    );
    expect(refersTo('parcels'), isTrue);
    state.deleteRecord('commodities', state.scenario.commodities.firstWhere((c) => c['id'] == 'parcels'));
    expect(state.scenario.commodities.map((c) => c['id']), ['food']);
    expect(refersTo('parcels'), isFalse);
  });

  testWidgets('node list per commodity', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    state.chooseProblem('Zwei Güter');
    state.setTab(DataTab.nodes);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    // all: the sums - Berlin 25 + 15
    expect(find.text('40'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pakete'));
    await tester.pump();
    expect(state.solutionPart, 'parcels');
    expect(find.text('Nachfrage je Gut'), findsNothing); // short: the commodity is in the chooser
    expect(find.text('Nachfrage'), findsOneWidget);
    expect(find.text('15'), findsWidgets); // Berlin
    expect(find.text('40'), findsWidgets); // plant: parcels 40
  });
}
