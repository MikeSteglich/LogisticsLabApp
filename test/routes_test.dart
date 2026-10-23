/// Courses of the edges along the roads: a failed request is tried again - not shown straight for good.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('failed course is loaded again', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    final python = Platform.isWindows ? 'python' : 'python3';
    await tester.runAsync(
      () => state.setBackendSettings(
        BackendSettings(executable: python, arguments: ['${Directory.current.path}/test/fixtures/flaky_core.py']),
      ),
    );
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    expect(state.scenario.usesRoads, isTrue);
    const a = LatLng(52.30, 13.26), b = LatLng(52.52, 13.40);

    await tester.runAsync(() async {
      expect(state.edgePoints(a, b).length, 2); // straight until loaded
      // first request fails, the next attempt after 2 s succeeds
      for (var i = 0; i < 60 && state.edgePoints(a, b).length == 2; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    });
    expect(state.edgePoints(a, b).length, 3); // along the "roads"
    expect(state.routesMissing, 0);
    expect(state.routesLoading, 0);

    // another file with the same coordinates: the course is kept
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    expect(state.edgePoints(a, b).length, 3);

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
