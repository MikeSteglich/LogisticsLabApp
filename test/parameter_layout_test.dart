/// Parameters tab: start and end (source and sink) side by side in one row.
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
  testWidgets('start and end in one row', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    await tester.pumpWidget(LogisticsLabApp(state: state));
    Future<void> sameRow(String a, String b) async {
      state.setTab(DataTab.parameters);
      await tester.pump();
      final ya = tester.getTopLeft(find.text(a).last).dy, yb = tester.getTopLeft(find.text(b).last).dy;
      final xa = tester.getTopLeft(find.text(a).last).dx, xb = tester.getTopLeft(find.text(b).last).dx;
      expect(ya, yb, reason: '$a / $b in one row');
      expect(xa, lessThan(xb), reason: '$a left of $b');
    }

    state.chooseProblem('Weg nach Cottbus'); // name, start, end: start would be right of the name
    await sameRow('Start', 'Ziel');
    state.chooseProblem('Rundreise');
    state.edit(() => state.problem!.parameters['tourType'] = 'path');
    await sameRow('Start', 'Ziel');
    state.newProblem('maxflow'); // name, flow, source, sink
    await sameRow('Quelle', 'Senke');
  });
}
