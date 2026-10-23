/// Before solving: required values of the nodes (e.g. supply and demand of a tpp) and roles without nodes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/ui/map_view.dart';
import 'dart:io';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('a tpp without supply and demand is not sent to the core', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    final s = Scenario.empty();
    s.addProblem('tpp', 'Transport', {});
    state.openScenario(s);
    state.scenario.matrix['matrixSource'] = 'beeline';

    // no nodes at all
    expect(state.nodeProblems, [
      'Keine Anbieter im Problem – im Knoten-Tab die Rolle vergeben',
      contains('Nachfrager'),
    ]);

    // nodes without values
    state.edit(() => state.scenario.addNode(const LatLng(52.3, 13.2), roles: ['supplier'])..json['name'] = 'Werk');
    state.edit(() => state.scenario.addNode(const LatLng(52.5, 13.4), roles: ['customer'])..json['name'] = 'Berlin');
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'error');
    expect(state.message, contains('Angebot fehlt bei: Werk'));
    expect(state.message, contains('Nachfrage fehlt bei: Berlin'));

    // a wrong value
    state.edit(() {
      state.scenario.node('N1')!['supply'] = -5;
      state.scenario.node('N2')!['demand'] = 10;
    });
    expect(state.nodeProblems, ['Angebot ist ungültig bei: Werk']);
    state.edit(() => state.scenario.node('N1')!['supply'] = 10);
    expect(state.nodeProblems, isEmpty);
  });

  testWidgets('one role per problem - the roles of other problems stay', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.selectNode('D1'); // candidate, depot, transit - no role of the tpp
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    final d1 = state.scenario.node('D1')!;
    final mask = find.byType(FilterChip);
    await tester.tap(find.descendant(of: mask, matching: find.text('Anbieter')).last);
    await tester.pump();
    expect(d1.roles, containsAll(['supplier', 'candidate', 'depot', 'transit']));
    await tester.tap(find.descendant(of: mask, matching: find.text('Nachfrager')).last);
    await tester.pump();
    expect(d1.roles, contains('customer'));
    expect(d1.roles, isNot(contains('supplier'))); // replaced
    expect(d1.roles, containsAll(['candidate', 'depot', 'transit'])); // other problems
    // two roles of the problem, e.g. from an old file: checked before solving
    state.edit(() => d1.roles = [...d1.roles, 'supplier']);
    expect(state.nodeProblems, contains(startsWith('Mehr als eine Rolle im Problem bei: Lager Wildau')));
  });
}
