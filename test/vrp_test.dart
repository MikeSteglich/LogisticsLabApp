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
import 'package:logisticslab_app/model/clock.dart';
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

    // no waiting at the depot: a tour leaves as late as its first time window needs - with a fixed start all leave
    // at 07:00 and wait at the customers
    expect(routes.any((r) => (r as Map)['start'] as num > 420), isTrue);
    // a tour of the overview highlighted - a section instead of it, a second tap removes it
    state.selectRoute(1);
    expect(state.selectedRoute, 1);
    final second = legs.indexWhere((l) => l['route'] == 0);
    state.selectFlow(second);
    expect(state.selectedRoute, isNull);
    expect(state.selectedFlow, second);
    state.selectRoute(0);
    expect(state.selectedFlow, isNull);
    state.selectRoute(0);
    expect(state.selectedRoute, isNull);
    state.edit(() => state.problem!.parameters['fixedStart'] = true);
    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    final fixed = (state.solution!.results!['routes'] as List).cast<Map>();
    expect(fixed.every((r) => r['start'] == 420), isTrue);
    expect((state.solution!.results!['summary'] as Map)['totalWaitingTime'], greaterThan(0));
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });

  testWidgets('customer mask: the time window as times of the day', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    state.chooseProblem('Touren ab Wildau');
    state.selectNode('B');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    expect(find.text('Zeitfenster (Uhrzeit)'), findsOneWidget);
    expect(find.text('Servicezeit (min)'), findsOneWidget);
    // the data of Berlin in the list and on the map (hover): demand, service time, time window
    expect(find.text('Zeitfenster'), findsOneWidget); // column of the list
    expect(find.text('08:00 – 12:00'), findsOneWidget);
    expect([for (final (f, v) in state.nodeData(state.scenario.node('B')!)) '${f.key} $v'], [
      'demand 40',
      'serviceTime 10 min',
      'timeWindow 08:00 – 12:00',
    ]);
    // Berlin: 08:00 to 12:00 (480 and 720 minutes)
    Finder field(String text) => find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);
    expect(field('08:00'), findsOneWidget);
    final latest = field('12:00');
    expect(latest, findsOneWidget);
    final input = find.descendant(of: find.byKey(const ValueKey('timeWindow|1')), matching: find.byType(TextField));
    await tester.enterText(input, '13:30');
    await tester.pump();
    expect(state.scenario.node('B')!['timeWindow'], [480, 810]);
    await tester.enterText(input, '13:3x');
    await tester.pump();
    expect(find.textContaining('Uhrzeit wie 08:30'), findsOneWidget);
    expect(state.scenario.node('B')!['timeWindow'], [480, 810]); // unchanged
    await tester.enterText(input, '');
    await tester.pump();
    expect(state.scenario.node('B')!['timeWindow'], [480, null]); // open end
    // the depot: start and latest return
    state.selectNode('D1');
    await tester.pump();
    expect(
      find.text('Einsatzzeit (Start, späteste Rückkehr)'),
      findsWidgets,
    ); // column of the list and field of the mask
    expect(find.text('07:00 – 18:00'), findsOneWidget); // the list
    expect(field('07:00'), findsOneWidget);
    expect(field('18:00'), findsOneWidget);
  });

  test('clock: times of the day in the time unit of the scenario', () {
    const min = Clock('min'), h = Clock('h');
    expect(min.format(510), '08:30');
    expect(min.format(1500), '01:00 (+1)');
    expect(min.parse('8:30'), 510);
    expect(min.parse('08.30'), 510);
    expect(min.parse('8'), 480);
    expect(min.parse('25:00'), isNull);
    expect(min.parse('8:75'), isNull);
    expect(h.parse('7:30'), 7.5);
    expect(h.format(7.5), '07:30');
    expect(min.duration(476.5), '7:57 h');
  });
}
