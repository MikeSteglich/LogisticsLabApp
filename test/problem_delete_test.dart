/// Problems of a file: duplicated (parameters copied, behind the original) and deleted from the problem menu (asked
/// first, the next one chosen, the last one kept).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('duplicate and delete in the state', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    final names = [for (final p in state.scenario.problems) p.name];
    final first = names.first;
    state.chooseProblem(first);
    state.duplicateProblem(first);
    final copy = '$first (Kopie)';
    expect(state.problemName, copy);
    expect([for (final p in state.scenario.problems) p.name], [first, copy, ...names.skip(1)]);
    // a copy of its own: changing it leaves the original
    state.problem!.parameters['probe'] = 1;
    expect(state.scenario.problem(first)!.parameters.containsKey('probe'), isFalse);
    expect(state.dirty, isTrue);

    state.deleteProblem(copy);
    expect([for (final p in state.scenario.problems) p.name], names);
    expect(state.problemName, names[1]); // the next one
    for (final n in names.skip(1)) {
      state.deleteProblem(n);
    }
    state.deleteProblem(first); // the last one stays
    expect([for (final p in state.scenario.problems) p.name], [first]);
    expect(state.problemName, first);
    expect(state.scenario.nodes, isNotEmpty);
  });

  testWidgets('deleted from the problem menu after the question', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    final names = [for (final p in state.scenario.problems) p.name];
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Löschen …').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Problem löschen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();
    expect([for (final p in state.scenario.problems) p.name], [names[0], ...names.skip(2)]);
  });
}
