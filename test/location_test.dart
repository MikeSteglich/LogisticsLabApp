/// Discrete location: warehouse location, p-median, p-centre, set and maximal covering - checks, solutions, the
/// table of the locations and the radius on the map.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/location_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/map_view.dart';

Future<AppState> _state(WidgetTester tester, String file) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('test/fixtures/$file').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
  return state;
}

final _stdio = Platform.environment['LOGLAB_STDIO'] == null;

void main() {
  test('the location problems in the menu', () {
    expect(
      [for (final m in modulesByGroup()[ModuleGroup.location]!) m.type],
      ['wlp', 'pmedian', 'pcentre', 'scp', 'mcp'],
    );
  });

  testWidgets('p-median: candidates and customers, p checked', (tester) async {
    final state = await _state(tester, 'drogma.dlpx.llab');
    state.chooseProblem('drogma');
    expect(state.problemRoles, ['candidate', 'customer']);
    expect(state.nodeProblems, isEmpty);
    state.edit(() => state.problem!.parameters['p'] = 7);
    expect(state.nodeProblems, contains('7 Standorte gewünscht, aber nur 6 Kandidaten'));
    // the budget of maximal covering: opening costs - without them the number of locations
    final mcp = modules['mcp']!;
    expect([for (final f in mcp.visibleParameters({})) f.label], contains('field.budget'));
    expect([
      for (final f in mcp.visibleParameters({'useFixedCosts': false})) f.label,
    ], contains('field.maxLocations'));
  });

  testWidgets('the number of locations entered in the parameters: an integer', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'drogma.dlpx.llab');
    state.chooseProblem('drogma');
    state.setTab(DataTab.parameters);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    final field = find.descendant(of: find.byKey(const ValueKey('drogma|de|p')), matching: find.byType(TextField));
    await tester.enterText(field, '5');
    await tester.pump();
    expect(state.problem!.parameters['p'], isA<int>());
    expect(state.problem!.parameters['p'], 5);
  });

  testWidgets('p-median solved: the open locations, every customer assigned', skip: _stdio, (tester) async {
    final state = await _state(tester, 'drogma.dlpx.llab');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.chooseProblem('drogma');
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    expect(state.openNodes.values.where((o) => o).length, 4);
    expect(state.connections.length, 30);
    // p as written by older versions of the number field: 5.0
    state.edit(() => state.problem!.parameters['p'] = 5.0);
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    expect(state.openNodes.values.where((o) => o).length, 5);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });

  testWidgets('covering solved: the radius on the map, the customers outside it', skip: _stdio, (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'europa-vertrieb.dlpx.llab');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    // set covering: every customer within 1000 km
    state.chooseProblem('europa-vertrieb (Set Covering)');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    // before solving the radius around every candidate
    expect(tester.widget<CircleLayer>(find.byType(CircleLayer)).circles.length, 4);
    await tester.runAsync(state.solve);
    await tester.pump();
    expect(state.message, isNull);
    final summary = state.solution!.results!['summary'] as Map;
    expect(summary['nrOfUncovered'], 0);
    expect(find.text('Zuordnung der Kunden'), findsOneWidget);
    // with the solution only around the open locations
    expect(
      tester.widget<CircleLayer>(find.byType(CircleLayer)).circles.length,
      state.openNodes.values.where((o) => o).length,
    );
    // maximal covering with a budget: not every customer
    state.chooseProblem('europa-vertrieb (Maximal Covering)');
    await tester.runAsync(state.solve);
    await tester.pump();
    final mcp = state.solution!.results!['summary'] as Map;
    expect(mcp['coverage'], lessThan(1));
    expect(find.textContaining('Nicht abgedeckt:'), findsOneWidget);
    // a radius no candidate reaches: refused before solving
    state.chooseProblem('europa-vertrieb (Set Covering)');
    state.edit(() => state.problem!.parameters['radius'] = 10);
    await tester.runAsync(state.solve);
    expect(state.message, contains('no candidate within the radius'));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });
}
