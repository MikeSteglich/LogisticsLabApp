/// How the nodes are served in a solution: supply shipped completely or partly, demand met completely or partly,
/// customers with several suppliers - on the map (badge, tooltip) and in the solution tab (cards, filter, table).
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
import 'package:logisticslab_app/ui/map_view.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline';
  return state;
}

void main() {
  testWidgets('nodes served partly and by several suppliers', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    // a second supplier, Berlin needs more than there is: supply 150, demand 180
    final d1 = state.scenario.node('D1')!;
    d1.roles = ['supplier'];
    d1['supply'] = 50;
    state.scenario.node('B')!['demand'] = 120;
    state.solutions[state.problemName!] = SolutionState({
      'status': 'solution',
      'results': {
        'objVal': 100,
        'summary': {'totalCosts': 100},
        'nodes': {
          'W': {'flow': 100},
          'D1': {'flow': 20},
          'B': {'flow': 95},
          'P': {'flow': 25},
          'F': {'flow': 0},
          'C': {'flow': 0},
        },
        'assignments': [
          {'from': 'W', 'to': 'B', 'flow': 75, 'rate': 1},
          {'from': 'W', 'to': 'P', 'flow': 25, 'rate': 1},
          {'from': 'D1', 'to': 'B', 'flow': 20, 'rate': 1},
        ],
      },
    }, state.revision);

    final a = state.analysis!;
    expect(a.use('W')!.notFull, isFalse); // supply shipped completely
    expect(a.use('D1')!.share, closeTo(0.4, 1e-9)); // 20 of 50
    expect(a.use('B')!.share, closeTo(95 / 120, 1e-9));
    expect(a.use('B')!.multiple, isTrue);
    expect(a.use('F')!.unused, isTrue);
    expect(a.missing('supplier'), 30);
    expect(a.missing('customer'), 25 + 20 + 15);
    expect(a.multipleReceivers, 1);

    state.setTab(DataTab.solution);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();

    // cards and filter of the solution tab
    expect(find.text('Ungenutztes Angebot'), findsOneWidget);
    expect(find.text('Ungedeckter Bedarf'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Nachfrager mit mehreren Anbietern'), findsOneWidget);
    expect(find.text('Bedarf nicht gedeckt  3'), findsOneWidget);
    expect(find.text('Angebot nicht ausgeschöpft  1'), findsOneWidget);
    await tester.tap(find.text('Mehrere Anbieter  1'));
    await tester.pumpAndSettle();
    expect(find.text('79 %'), findsOneWidget); // Berlin only

    // map: badge with the number of suppliers, tooltip with the quantities
    expect(find.descendant(of: find.byType(MarkerLayer), matching: find.text('2')), findsOneWidget);
    final tip = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? t.richMessage?.toPlainText() ?? '')
        .firstWhere((m) => m.startsWith('Berlin'));
    expect(tip, contains('Nachfrage 120'));
    expect(tip, contains('erhalten 95'));
    expect(tip, contains('von Werk Ludwigsfelde 75, Lager Wildau 20'));
  });

  testWidgets('less supply than demand - solved by the core', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    final state = await _state(tester);
    state.scenario.node('B')!['demand'] = 120; // demand 180, supply 100
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'solution');
    final a = state.analysis!;
    expect(a.use('W')!.notFull, isFalse);
    expect(a.missing('customer'), 80);
    expect(a.uses.where((u) => u.role == 'customer' && u.notFull), isNotEmpty);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
