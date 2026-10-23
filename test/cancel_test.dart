/// Cancelling a running solver: the core stops it, the app reports no error.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/cancel_test.dart
///
/// Without LOGLAB_STDIO the test is skipped.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('cancel a running solver', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no network needed
    // the vrp uses the whole time limit (guided local search)
    state.chooseProblem('Touren ab Wildau');
    state.problem!.parameters['maxSolvingTime'] = 30;

    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      final solving = state.solve();
      while (state.status != 'running' && watch.elapsed < const Duration(seconds: 30)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect(state.status, 'running');
      expect(state.jobId, isNotNull);
      await Future.delayed(const Duration(seconds: 1));
      await state.cancel();
      await solving.timeout(const Duration(seconds: 20));
      expect(watch.elapsed, lessThan(const Duration(seconds: 25))); // not the 30 s of the time limit
    });
    expect(state.lastResult, 'cancelled');
    expect(state.message, isNull); // no error dialog
    expect(state.solving, isFalse);

    // the next problem is solved normally
    state.chooseProblem('Transport direkt vom Werk');
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'solution');

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
