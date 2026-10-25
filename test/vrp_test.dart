/// Vehicle routing: tours of the vehicles from the depot, time windows, the checks before solving.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/vrp_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/map_view.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  return state;
}

void main() {
  testWidgets('vrp: depot and customers, vehicles, time windows checked', (tester) async {
    final state = await _state(tester);
    state.chooseProblem('Touren ab Wildau');
    expect(state.problemRoles, ['depot', 'customer']);
    expect(state.spec!.usesVehicles, isTrue);
    expect(state.nodeProblems, isEmpty);

    // time window: earliest after latest
    final tw = vrpSpec.roles.last.nodeFields.firstWhere((f) => f.key == 'timeWindow');
    expect(tw.validate([0, 240]), isNull);
    expect(tw.validate([60, null]), isNull); // open end
    expect(tw.validate([300, 240]), isNotNull);

    // no vehicles, a second depot
    state.edit(() {
      state.scenario.vehicles.clear();
      state.scenario.node('D2')!.roles = ['candidate', 'transit', 'depot'];
    });
    expect(state.nodeProblems, contains(startsWith('Noch keine Fahrzeuge')));
    expect(state.nodeProblems, contains(startsWith('Nur ein Depot möglich')));
  });

  testWidgets('vrp solved: tours of the vehicles with arrivals', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.chooseProblem('Touren ab Wildau');
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    final routes = state.solution!.results!['routes'] as List;
    // no number of trucks: as few tours as possible - a demand of 100 needs 2 trucks of 60
    expect(state.scenario.vehicles.single.containsKey('count'), isFalse);
    expect(routes.length, 2);
    expect((state.solution!.results!['summary'] as Map)['nrOfVehicles'], isNull);
    expect(state.routeNames, ['Tour 1 · LKW1', 'Tour 2 · LKW2']);
    final legs = state.connections;
    expect({for (final l in legs) l['route']}, {0, 1});
    expect(legs.every((l) => l['arrival'] is num), isTrue); // with time windows: the schedule
    for (final ri in [0, 1]) {
      final tour = legs.where((l) => l['route'] == ri).toList();
      expect(tour.first['from'], 'D1');
      expect(tour.last['to'], 'D1');
    }
    final summary = state.solution!.results!['summary'] as Map;
    expect(summary['totalLoad'], 100);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });

  testWidgets('customer mask: demand, service time and the time window in minutes', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    state.chooseProblem('Touren ab Wildau');
    state.selectNode('B');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('Zeitfenster (min)'), findsOneWidget);
    expect(find.text('frühestens'), findsOneWidget);
    expect(find.text('Servicezeit (min)'), findsOneWidget);
    // the latest end of Berlin: 240
    final latest = find.widgetWithText(TextField, '240');
    expect(latest, findsOneWidget);
    await tester.enterText(latest, '');
    await tester.pump();
    expect(state.scenario.node('B')!['timeWindow'], [0, null]); // open end
  });
}
