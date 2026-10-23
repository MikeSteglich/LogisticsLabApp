/// Button "look up coordinates" in the node mask - with the local solver (OSM geocoding, needs network).
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/geocode_test.dart
///
/// Without LOGLAB_STDIO the test is skipped.
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

void main() {
  testWidgets('look up coordinates', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()),
        name: 'brandenburg.llab');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    // real time for the child process and the OSM request
    Future<void> waitFor(Finder f) async {
      for (var i = 0; i < 300 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    // the search itself - in real time, this also starts the solver (a process started from the fake time of
    // testWidgets would never get ready)
    final direct = (await tester.runAsync(() => state.geocode('Hochschulring 1, Wildau')))!;
    expect(direct, isNotEmpty);
    expect(direct.first.position.latitude, closeTo(52.318, 0.01));

    state.selectNode('W');
    state.edit(() => state.node!.address = 'Hochschulring 1, Wildau');
    await tester.pump();
    final button = find.text('Koordinaten suchen');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    // several hits: choice
    await waitFor(find.byType(SimpleDialog));
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.byType(SimpleDialogOption).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final p = state.scenario.node('W')!.position;
    expect(p.latitude, closeTo(52.318, 0.01));
    expect(p.longitude, closeTo(13.630, 0.01));
    expect(find.textContaining('Position gesetzt'), findsOneWidget);

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
