/// A connection selected in the solution table is highlighted on the map (orange) - a second tap removes it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';
import 'package:logisticslab_app/ui/theme.dart';

void main() {
  testWidgets('selected connection of the solution', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(
      Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()),
      name: 'brandenburg.llab',
    );
    // straight lines - the map loads no roads
    state.scenario.matrix['matrixSource'] = 'beeline';
    // solution as the core sends it (llsol)
    state.solutions[state.problemName!] = SolutionState({
      'status': 'solution',
      'results': {
        'objVal': 100,
        'summary': {'totalCosts': 100},
        'assignments': [
          {'from': 'W', 'to': 'B', 'flow': 40, 'rate': 1},
          {'from': 'W', 'to': 'F', 'flow': 20, 'rate': 2},
        ],
      },
    }, state.revision);
    state.setTab(DataTab.solution);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    List<Polyline> orange() => [
      for (final l in tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)))
        for (final p in l.polylines)
          if (p.color == Ui.highlight) p,
    ];
    expect(orange(), isEmpty);

    // the name is in the table and on the map
    final inTable = find.descendant(of: find.byType(Table), matching: find.text('Frankfurt (Oder)'));
    await tester.tap(inTable);
    await tester.pump();
    expect(state.selectedFlow, 1);
    expect(orange().length, 1);
    expect(orange().single.points.last, state.scenario.node('F')!.position);

    await tester.tap(inTable);
    await tester.pump();
    expect(state.selectedFlow, isNull);
    expect(orange(), isEmpty);
  });
}
