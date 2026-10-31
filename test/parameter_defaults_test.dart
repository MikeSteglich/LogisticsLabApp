/// The work from left to right: the parameters first - and in the empty fields the values the core takes for them.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('parameters first, the defaults of the core in the empty fields', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    expect(state.tab, DataTab.parameters);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    // the tabs in the order of the work
    final x = [
      for (final t in ['Parameter', 'Knoten', 'Netz', 'Lösung']) tester.getTopLeft(find.text(t).first).dx,
    ];
    expect(x, [...x]..sort());

    List<String?> hints() => [
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) f.decoration?.hintText,
    ];
    state.chooseProblem(state.scenario.problems.firstWhere((p) => p.type == 'tpp').name);
    await tester.pump();
    expect(hints(), containsAll(['300', '0,001', '0']));

    state.chooseProblem(state.scenario.problems.firstWhere((p) => p.type == 'mincostflow').name);
    await tester.pump();
    expect(hints(), containsAll(['60', '0,001']));
    expect(state.problem!.parameters.containsKey('maxSolvingTime'), isFalse); // shown, not stored

    state.newProblem('vrp');
    await tester.pump();
    expect(hints(), containsAll(['10', 'keine Grenze']));
    expect(modules['tpp']!.nodeFieldsFor(['supplier'], {'useSupplyRanges': true}).last.hint, 'hint.likeSupply');
  });
}
