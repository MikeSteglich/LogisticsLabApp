/// Pickup and delivery: pickups with their delivery nodes, the checks, the tours with the load of the vehicle.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/pdp_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  state.chooseProblem('Abholen und Zustellen');
  return state;
}

void main() {
  testWidgets('pdp: depot, pickups and deliveries, the delivery node checked', (tester) async {
    final state = await _state(tester);
    expect(state.problemRoles, ['depot', 'pickup', 'delivery']);
    expect(state.nodeProblems, isEmpty);
    // the data of a pickup: amount and delivery node by its name
    expect(
      [for (final (f, v) in state.nodeData(state.scenario.node('W')!)) '${f.key} $v'],
      ['amount 30', 'deliveryTo Berlin'],
    );
    // the amount delivered to Berlin: from the pickups
    expect([for (final (f, v) in state.nodeData(state.scenario.node('B')!)) '${f.key} $v'].first, 'delivered 30');
    // a delivery node without the role
    state.edit(() => state.scenario.node('W')!['deliveryTo'] = 'D2');
    expect(state.nodeProblems, contains(startsWith('Zustellort ohne Rolle Zustellort bei: Werk Ludwigsfelde')));
    // renamed and deleted in the references too
    state.edit(() => state.scenario.node('W')!['deliveryTo'] = 'B');
    state.edit(() => state.scenario.renameNode('B', 'BER'));
    expect(state.scenario.node('W')!['deliveryTo'], 'BER');
    expect(state.scenario.usages('BER').map((u) => u.$1), contains('ui.use.deliveryTo'));
    state.edit(() => state.scenario.removeNode('BER'));
    expect(state.scenario.node('W')!.json.containsKey('deliveryTo'), isFalse);
    expect(state.nodeProblems, contains(contains('Zustellort')));
  });

  testWidgets('pickup mask: the delivery node chosen among the deliveries', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    state.selectNode('W');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('Abholmenge'), findsWidgets);
    final dropdown = find.byType(DropdownButtonFormField<String?>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // only the delivery nodes, by their names
    for (final name in ['Potsdam', 'Frankfurt (Oder)']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.descendant(of: find.byType(DropdownMenuItem<String?>), matching: find.text('Cottbus')), findsNothing);
    await tester.tap(find.descendant(of: find.byType(DropdownMenuItem<String?>), matching: find.text('Potsdam')).last);
    await tester.pumpAndSettle();
    expect(state.scenario.node('W')!['deliveryTo'], 'P');
    // Potsdam: its amount from both pickups, shown and not entered
    state.selectNode('P');
    await tester.pumpAndSettle();
    expect(find.text('Liefermenge'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '50 · Werk Ludwigsfelde 30 · Lager Brandenburg 20',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'pdp solved: every pickup before its delivery, the load within the capacity',
    skip: Platform.environment['LOGLAB_STDIO'] == null,
    (tester) async {
      final state = await _state(tester);
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      // the tours named after the name of the vehicle - not its id
      state.edit(() => state.scenario.vehicles.single['name'] = 'Sprinter');
      await tester.runAsync(state.solve);
      expect(state.message, isNull);
      expect(state.routeNames.first, 'Tour 1 · Sprinter1');
      final routes = (state.solution!.results!['routes'] as List).cast<Map>();
      expect(routes, isNotEmpty);
      final pairs = {
        for (final n in state.scenario.nodes)
          if (n['deliveryTo'] != null) n.id: '${n['deliveryTo']}',
      };
      for (final r in routes) {
        final nodes = (r['nodes'] as List).cast<String>();
        for (final MapEntry(key: p, value: d) in pairs.entries) {
          if (nodes.contains(p)) expect(nodes.indexOf(p), lessThan(nodes.lastIndexOf(d)), reason: '$p before $d');
        }
        final legs = (r['legs'] as List).cast<Map>();
        expect(legs.every((l) => (l['load'] as num) <= (r['capacity'] as num)), isTrue);
        expect(legs.last['load'], 0); // back at the depot empty
      }
      // every pickup on a tour
      expect({for (final r in routes) ...(r['nodes'] as List)}.containsAll(pairs.keys), isTrue);
      // the load in the table: + picked up, − delivered
      expect(state.connections.any((l) => l['load'] != null), isTrue);
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
    },
  );
}
