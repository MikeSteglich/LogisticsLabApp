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
      ['wlp', 'pmedian', 'pcentre', 'scp', 'mcp', 'contpmedian', 'contpcentre'],
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
    // the list of all nodes: the supply (capacity) of the candidates
    state.setTab(DataTab.nodes);
    await tester.pump();
    expect(find.text('Angebot'), findsOneWidget);
    expect(find.text('350'), findsWidgets);
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
    // a location tapped on the map (solution shown): all its assignments highlighted - one assignment instead of it
    state.setTab(DataTab.solution);
    final location = state.openNodes.entries.firstWhere((e) => e.value).key;
    state.tapNode(location);
    expect(state.highlightedNode, location);
    expect(state.tab, DataTab.solution);
    final own = state.connections.where((c) => c['from'] == location).length;
    expect(state.connections.where(state.touchesHighlighted).length, own);
    state.selectFlow(0);
    expect(state.highlightedNode, isNull);
    // the list of all nodes: the candidates of a covering with their operating costs (no capacities)
    state.setTab(DataTab.nodes);
    await tester.pump();
    expect(find.text('Betriebskosten'), findsWidgets);
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

  testWidgets('continuous location: the locations found on the map, adopted as candidates', skip: _stdio, (
    tester,
  ) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'lds-sued.clpx.llab');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.chooseProblem('lds-sued');
    expect(state.problemRoles, ['customer']);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.runAsync(state.solve);
    await tester.pump();
    expect(state.message, isNull);
    // two locations anywhere, every customer assigned to one of them
    expect(state.foundLocations.keys, ['F1', 'F2']);
    expect(state.connections.length, 28);
    expect(state.connections.every((c) => state.foundLocations.containsKey(c['from'])), isTrue);
    expect(state.nameOf('F2'), 'Standort 2');
    expect(find.text('Standort 1'), findsWidgets); // map and table
    // hover of a location found: its name, coordinates, customers and quantity
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && (w.richMessage?.toPlainText() ?? '').startsWith('Standort 1\n')),
      findsOneWidget,
    );
    // the coordinates of the locations found in the table
    final f1 = state.foundLocations['F1']!;
    expect(
      find.text('${state.strings.fixed(f1.latitude, 5)} / ${state.strings.fixed(f1.longitude, 5)}'),
      findsOneWidget,
    );
    // the locations become candidates of the scenario
    await tester.tap(find.text('Als Kandidaten übernehmen'));
    await tester.pump();
    final candidates = state.scenario.nodes.where((n) => n.roles.contains('candidate')).toList();
    expect([for (final n in candidates) n.name], ['Standort 1', 'Standort 2']);
    expect(candidates.first.position.latitude, closeTo(state.foundLocations['F1']!.latitude, 1e-5));
    expect(candidates.first.position.longitude, closeTo(state.foundLocations['F1']!.longitude, 1e-5));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });

  testWidgets(
    'weighted with the demands: another objective, its label and the rating of every assignment',
    skip: _stdio,
    (tester) async {
      MapView.showTiles = false;
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = await _state(tester, 'lds-sued.clpx.llab');
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      // different demands - with demands 1 the weighting does not matter
      state.edit(() {
        for (final (i, n) in state.scenario.nodes.indexed) {
          n['demand'] = [1, 5, 20][i % 3];
        }
        state.scenario.addProblem('contpmedian', 'Median', {'p': 2});
      });
      await tester.pumpWidget(LogisticsLabApp(state: state));
      for (final (name, label, weightedLabel) in [
        ('lds-sued', 'Längste Entfernung', 'Größte gewichtete Entfernung'),
        ('Median', 'Summe der Entfernungen', 'Summe der gewichteten Entfernungen'),
      ]) {
        final objVals = <bool, num>{};
        for (final weighted in [false, true]) {
          state.chooseProblem(name);
          state.edit(() => state.problem!.parameters['isDemandWeighted'] = weighted);
          await tester.runAsync(state.solve);
          await tester.pump();
          expect(state.message, isNull, reason: name);
          final objVal = state.solution!.results!['objVal'] as num;
          objVals[weighted] = objVal;
          expect(find.text(weighted ? weightedLabel : label), findsOneWidget, reason: '$name $weighted');
          // the ratings of the assignments: their sum or their maximum is the objective value
          final ratings = [for (final a in state.connections) a['costs'] as num];
          final total = name == 'Median' ? ratings.reduce((a, b) => a + b) : ratings.reduce((a, b) => a > b ? a : b);
          expect(total, closeTo(objVal, 1e-6 * objVal), reason: '$name $weighted');
          expect(find.text('Bewertung'), findsOneWidget);
        }
        expect(objVals[true], greaterThan(objVals[false]! * 1.5), reason: name);
      }
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    },
  );

  testWidgets('capacities: the smallest capacity per location suggested, too small capacities refused', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'lds-sued.clpx.llab');
    state.chooseProblem('lds-sued');
    state.edit(() => state.problem!.parameters['isCapacitated'] = true);
    final total = state.totalDemand;
    // two locations: at least half of the total demand each
    expect(state.minCapacity, (total / 2).ceil());
    state.setTab(DataTab.parameters);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('mindestens ${state.strings.number(state.minCapacity!)}'), findsOneWidget);
    state.edit(() => state.problem!.parameters['capacities'] = state.minCapacity! - 1);
    expect(state.nodeProblems, contains(startsWith('Kapazität je Standort zu klein')));
    state.edit(() => state.problem!.parameters['capacities'] = state.minCapacity!);
    expect(state.nodeProblems, isEmpty);
    // discrete: the p largest capacities of the candidates (drogma: 350 each)
    state.openScenario(Scenario.parse(File('test/fixtures/drogma.dlpx.llab').readAsStringSync()));
    state.chooseProblem('drogma');
    expect(state.nodeProblems, isEmpty);
    state.edit(() => state.problem!.parameters['p'] = 1);
    expect(state.nodeProblems, contains(startsWith('Die Kapazitäten der Kandidaten (350)')));
  });
}
