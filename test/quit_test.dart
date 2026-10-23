/// Quitting with unsaved changes: the app asks - cancel keeps it open, "don't save" quits.
library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('quit with unsaved changes', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()), name: 'b.llab');
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    // saved: no question
    state.dirty = false;
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);

    // changed: the question - cancel keeps the app open
    state.edit(() => state.node!.name = 'Werk');
    var answer = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(find.text('Änderungen an „b.llab“ speichern?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    expect(await answer, AppExitResponse.cancel);

    // don't save: quits
    answer = tester.binding.handleRequestAppExit();
    await tester.pump();
    await tester.tap(find.text('Nicht speichern'));
    await tester.pump();
    expect(await answer, AppExitResponse.exit);
  });
}
