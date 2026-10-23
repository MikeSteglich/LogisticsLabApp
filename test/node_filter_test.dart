/// Filter of the node list by the roles of the problem - a node follows its new role into the other list.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('node filter', (tester) async {
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
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    List<String> ids() => [for (final n in state.filteredNodes) n.id];

    // chips with the counts: all, suppliers, customers, others (the depots)
    expect(find.text('Alle  7'), findsOneWidget);
    expect(find.text('Anbieter  1'), findsOneWidget);
    expect(find.text('Nachfrager  4'), findsOneWidget);
    expect(find.text('Sonstige  2'), findsOneWidget);

    await tester.tap(find.text('Anbieter  1'));
    await tester.pump();
    expect(ids(), ['W']);
    expect(state.selectedNode, 'W');

    // the supplier becomes a customer - the list switches to the customers, W stays selected
    state.edit(() => state.node!.roles = ['customer']);
    await tester.pump();
    expect(state.nodeFilter, 'customer');
    expect(ids(), contains('W'));
    expect(state.selectedNode, 'W');
    expect(find.text('Nachfrager  5'), findsOneWidget);

    // a new node gets the role of the list shown
    state.addNode(const LatLng(52.4, 13.0));
    await tester.pump();
    expect(state.node!.roles, ['customer']);
    expect(state.nodeFilter, 'customer');

    // nodes without a role in the problem
    await tester.tap(find.text('Sonstige  2'));
    await tester.pump();
    expect(ids(), ['D1', 'D2']);
    expect(state.selectedNode, 'D1');

    // a node chosen on the map that is not in the list: the filter follows it
    state.selectNode('B');
    await tester.pump();
    expect(state.nodeFilter, 'customer');
  });
}
