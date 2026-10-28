/// A new scenario without a problem (none of a type given), and the transshipment nodes of a network flow as a role
/// in the node mask.
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
  testWidgets('new: no problem; a network flow: the role transshipment node in the mask', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.chooseProblem('Distribution über die Lager');
    state.selectNode(state.scenario.nodes.first.id);
    state.setTab(DataTab.nodes);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'Umladeknoten'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Umladeknoten'));
    await tester.pump();
    expect(state.scenario.nodes.first.roles, contains('transit'));
    expect(state.isTransit(state.scenario.nodes.first), isTrue);

    // new scenario: no transportation problem of its own
    state.saved(name: 'x.llab'); // no question about changes
    await tester.tap(find.byTooltip('Neu').evaluate().isEmpty ? find.text('Neu') : find.byTooltip('Neu'));
    await tester.pumpAndSettle();
    expect(state.scenario.problems, isEmpty);
    expect(state.problem, isNull);
    expect(find.text('Kein Problem'), findsWidgets);
  });
}
