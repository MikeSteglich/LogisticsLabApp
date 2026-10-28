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
    // whether a customer is served: in the list (a row of its own if not) and on the map
    state.setTab(DataTab.solution);
    await tester.pump();
    final assigned = {for (final a in state.connections) a['to']};
    final customers = [
      for (final n in state.scenario.nodes)
        if (n.active && n.roles.contains('customer')) n,
    ];
    final unserved = customers.where((n) => !assigned.contains(n.id)).toList();
    expect(unserved, isNotEmpty);
    expect(find.text('Beliefert'), findsOneWidget);
    expect(find.text('nein'), findsNWidgets(unserved.length));
    expect(state.customerServed(unserved.first.id), isFalse);
    expect(state.customerServed(customers.firstWhere((n) => assigned.contains(n.id)).id), isTrue);
    expect(state.customerServed(state.openNodes.keys.first), isNull); // a candidate
    // the evaluation as for a transportation problem: the demand not met, customers and open locations
    final analysis = state.analysis!;
    num demand(Node n) => (n['demand'] as num?) ?? 1;
    expect(analysis.missing('customer'), closeTo(unserved.fold<num>(0, (a, n) => a + demand(n)), 1e-6));
    expect(analysis.ofRole('candidate').length, state.openNodes.values.where((o) => o).length);
    expect(find.text('Ungedeckter Bedarf'), findsOneWidget);
    expect(find.text('Kunden mit mehreren Standorten'), findsOneWidget);
    // a radius no candidate reaches: refused before solving
    state.chooseProblem('europa-vertrieb (Set Covering)');
    state.edit(() => state.problem!.parameters['radius'] = 10);
    await tester.runAsync(state.solve);
    expect(state.message, contains('Der Radius ist zu klein'));
    state.chooseProblem('europa-vertrieb (Maximal Covering)');
    state.setTab(DataTab.solution);
    await tester.pump();
    // the open locations of the maximal covering become suppliers - with the quantity assigned to them
    final open = [
      for (final e in state.openNodes.entries)
        if (e.value) e.key,
    ];
    await tester.tap(find.text('Offene Standorte als Anbieter'));
    await tester.pump();
    for (final id in open) {
      final n = state.scenario.node(id)!;
      expect(n.roles, containsAll(['candidate', 'supplier']));
      expect(n['supply'], closeTo((state.solution!.results!['nodes'] as Map)[id]['load'] as num, 1e-6));
    }
    await tester.pump(const Duration(seconds: 5)); // the note
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
    // the evaluation as for the discrete problems: the locations found and every customer served
    final analysis = state.analysis!;
    expect([for (final u in analysis.ofRole('candidate')) u.node.name], ['Standort 1', 'Standort 2']);
    expect(analysis.ofRole('customer').length, 28);
    expect(analysis.missing('customer'), closeTo(0, 1e-6));
    expect(
      analysis.ofRole('candidate').fold<num>(0, (a, u) => a + u.actual),
      closeTo(analysis.ofRole('customer').fold<num>(0, (a, u) => a + u.actual), 1e-6),
    );
    expect(find.text('Ungedeckter Bedarf'), findsOneWidget);
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
        // capacities without isCapacitated: a warning of the core - in the language of the app
        state.scenario.addProblem('contpmedian', 'Median', {'p': 2, 'capacities': 1000, 'isCapacitated': false});
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
          if (name == 'Median') {
            expect(
              find.text('Die Kapazitäten werden nicht berücksichtigt, weil „Kapazitäten beachten“ aus ist'),
              findsOneWidget,
            );
          }
        }
        expect(objVals[true], greaterThan(objVals[false]! * 1.5), reason: name);
      }
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    },
  );

  testWidgets(
    'covering: the smallest radius suggested and entered, too small radius and no opening costs refused',
    skip: _stdio,
    (tester) async {
      MapView.showTiles = false;
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = await _state(tester, 'europa-vertrieb.dlpx.llab');
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      state.chooseProblem('europa-vertrieb (Set Covering)');
      state.tab = DataTab.parameters;
      await tester.pumpWidget(LogisticsLabApp(state: state));
      // computed by the core in the background - here at once
      expect(state.coveringRadius, isNull);
      await tester.runAsync(state.loadCoveringRadius);
      await tester.pump();
      expect(state.coveringRadius!['customer'], 'D0006');
      final min = state.minRadius!;
      expect(min, closeTo(808.36, 0.01));
      // the button in the field enters it
      await tester.tap(find.byIcon(Icons.straighten));
      await tester.pump();
      expect(state.problem!.parameters['radius'], min);
      expect(state.nodeProblems, isEmpty);
      await tester.runAsync(state.solve);
      expect(state.message, isNull);
      // smaller: refused before solving, with the customer outside
      state.edit(() => state.problem!.parameters['radius'] = 800);
      expect(state.nodeProblems.single, startsWith('Der Radius ist zu klein: mindestens 808,36 km'));
      // the radius itself does not compute it again
      expect(state.coveringRadius, isNotNull);
      // opening costs considered, but none: refused
      state.edit(() {
        state.problem!.parameters['radius'] = 1000;
        state.problem!.parameters['useFixedCosts'] = true;
        for (final n in state.scenario.nodes) {
          n['fixedCost'] = null;
        }
      });
      expect(state.nodeProblems.single, startsWith('Die Betriebskosten sollen berücksichtigt werden'));
      await tester.pump(const Duration(seconds: 1)); // the delay before computing the radius again
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    },
  );

  testWidgets(
    'continuous p-median with cost factors: the objective weighted, the plain sum of the distances apart',
    skip: _stdio,
    (tester) async {
      MapView.showTiles = false;
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'language': 'de'});
      final state = (await tester.runAsync(AppState.create))!;
      state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
      state.scenario.matrix['matrixSource'] = 'beeline';
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      state.chooseProblem('Freie Standorte (CLP, p-Median)');
      state.edit(() {
        state.problem!.parameters['isDemandWeighted'] = false;
        // every distance counts twice
        for (final n in state.scenario.nodes) {
          if (n.roles.contains('customer')) n['costFactor'] = 2;
        }
      });
      state.tab = DataTab.solution;
      await tester.pumpWidget(LogisticsLabApp(state: state));
      await tester.runAsync(state.solve);
      await tester.pump();
      expect(state.message, isNull);
      // cost factors: the objective is weighted, the plain sum another value
      expect(find.text('Summe der gewichteten Entfernungen'), findsOneWidget);
      expect(find.text('Summe der Entfernungen (ungewichtet)'), findsOneWidget);
      // without cost factors both are the same - the plain sum left out
      state.edit(() {
        for (final n in state.scenario.nodes) {
          n['costFactor'] = null;
        }
      });
      await tester.runAsync(state.solve);
      await tester.pump();
      expect(find.text('Summe der Entfernungen'), findsOneWidget);
      expect(find.text('Summe der Entfernungen (ungewichtet)'), findsNothing);
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    },
  );

  testWidgets('capacitated p-median: single-source or the demands split among the locations', skip: _stdio, (
    tester,
  ) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'drogma.dlpx.llab');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.chooseProblem('drogma');
    // scarce capacities: a bit more than the total demand of the p locations
    final cap = (state.totalDemand / 4 * 1.02).ceil();
    state.edit(() {
      for (final n in state.scenario.nodes) {
        if (n.roles.contains('candidate')) n['capacity'] = cap;
      }
      state.problem!.parameters['isCapacitated'] = true;
    });
    state.tab = DataTab.parameters;
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('Jeder Kunde von genau einem Standort'), findsOneWidget);
    final objVals = <bool, num>{};
    for (final single in [true, false]) {
      state.edit(() => state.problem!.parameters['isSingleSource'] = single);
      state.tab = DataTab.solution;
      await tester.runAsync(state.solve);
      await tester.pump();
      expect(state.message, isNull);
      objVals[single] = state.solution!.results!['objVal'] as num;
      final rows = state.connections;
      final customers = {for (final a in rows) a['to']};
      // multi-source: some customers from two locations, with their shares - the ratings sum up to the objective
      expect(rows.length > customers.length, !single);
      expect(find.text('Anteil'), single ? findsNothing : findsOneWidget);
      final sum = rows.fold<num>(0, (t, a) => t + (a['costs'] as num));
      expect(sum, closeTo(objVals[single]!, 1e-3 * objVals[single]!));
      for (final n in (state.solution!.results!['nodes'] as Map).values) {
        expect((n as Map)['load'] as num? ?? 0, lessThanOrEqualTo(cap + 1e-3)); // the tolerance of the solver
      }
    }
    expect(objVals[false], lessThan(objVals[true]!));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });

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
