/// TSP: round trip, passage from a start to an end node ("Durchfahrt") and open end with the local solver.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/tsp_test.dart
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
  return state;
}

void main() {
  testWidgets('a tsp uses all active nodes, the end only for a passage', (tester) async {
    final state = await _state(tester);
    state.newProblem('tsp');
    expect(state.problem!.parameters['tourType'], 'round');
    expect(state.scenario.nodes.where((n) => n.active).every(state.isRelevant), isTrue);
    final end = state.spec!.parameters.firstWhere((f) => f.key == 'endNode');
    expect(end.isVisible(state.problem!.parameters), isFalse);
    state.edit(() => state.problem!.parameters['tourType'] = 'path');
    expect(end.isVisible(state.problem!.parameters), isTrue);
  });

  testWidgets('round trip, passage and open end', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    final state = await _state(tester);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.newProblem('tsp');
    final nodes = state.scenario.nodes.where((n) => n.active).length;
    Future<List<Map<String, dynamic>>> solve(Map<String, dynamic> parameters) async {
      state.edit(() => state.problem!.parameters.addAll(parameters));
      await tester.runAsync(state.solve);
      expect(state.message, isNull, reason: '$parameters');
      expect(state.isRoute, isTrue);
      return state.connections;
    }

    // round trip: back to the start, every node once
    var legs = await solve({'tourType': 'round', 'startNode': 'D1'});
    expect(legs.length, nodes);
    expect(legs.first['from'], 'D1');
    expect(legs.last['to'], 'D1');
    expect([for (final l in legs) l['leg']], [for (var i = 1; i <= nodes; i++) i]);
    final length = legs.fold<num>(0, (sum, l) => sum + (l['value'] as num));
    expect(state.solution!.results!['summary']['tourLength'], closeTo(length, 0.01));

    // passage from the plant to Cottbus
    legs = await solve({'tourType': 'path', 'startNode': 'W', 'endNode': 'C'});
    expect(legs.length, nodes - 1);
    expect(legs.first['from'], 'W');
    expect(legs.last['to'], 'C');

    // open end: no way back
    legs = await solve({'tourType': 'open', 'startNode': 'W'});
    expect(legs.length, nodes - 1);
    expect(legs.last['to'], isNot('W'));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });

  testWidgets('tsp: each edge directed or undirected', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    state.newProblem('tsp');
    state.newNetwork('Straßen', directed: false);
    expect(state.addEdge('W', 'B'), isTrue);
    final net = state.network!;
    final e = net.edges.single;
    expect(e.directedIn(net), isFalse);
    expect(net.hasEdge('B', 'W'), isTrue); // both ways
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('Werk Ludwigsfelde ↔ Berlin'), findsWidgets);

    // the edge one way only: kept at the edge, the network stays undirected
    await tester.tap(find.text('gerichtet  von → nach'));
    await tester.pump();
    expect(e['directed'], isTrue);
    expect(net.directed, isFalse);
    expect(net.hasEdge('B', 'W'), isFalse);
    expect(find.text('Werk Ludwigsfelde → Berlin'), findsWidgets);
    // back to the direction of the network: nothing at the edge
    await tester.tap(find.text('ungerichtet  ↔'));
    await tester.pump();
    expect(e.json.containsKey('directed'), isFalse);
  });

  testWidgets(
    'no tour over a missing way - one-way edge to the start',
    skip: Platform.environment['LOGLAB_STDIO'] == null,
    (tester) async {
      SharedPreferences.setMockInitialValues({'language': 'de'});
      final state = (await tester.runAsync(AppState.create))!;
      state.openScenario(Scenario.parse(File('test/fixtures/wandlitz-kanten-falsch.tspx.llab').readAsStringSync()));
      state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
      // from the Fischerstube only a one-way edge leads to it: no way back
      await tester.runAsync(state.solve);
      expect(state.lastResult, 'error');
      expect(state.message, contains('Fischerstube'));
      // the edge both ways: a tour without impossible sections
      final net = state.network!;
      state.edit(() => net.edges.firstWhere((e) => e.to == 'RES')['directed'] = null);
      await tester.runAsync(state.solve);
      expect(state.message, isNull);
      expect(state.connections.every((l) => l['value'] is num), isTrue);
      expect(state.solution!.results!['summary']['tourLength'], lessThan(1e6));
      await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
    },
  );
}
