/// The name of the problem in the parameters: typed letter by letter - the field keeps the focus, though the name
/// in the head of the window follows every letter.
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
  testWidgets('a new name typed letter by letter', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    state.setTab(DataTab.parameters);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();

    final label = find.text('Name des Problems');
    final field = find.descendant(
      of: find.ancestor(of: label, matching: find.byType(Column)).first,
      matching: find.byType(EditableText),
    );
    await tester.tap(field);
    await tester.pump();
    final editable = tester.state<EditableTextState>(field);
    var text = '';
    for (final letter in 'Bottleneck'.split('')) {
      text += letter;
      tester.testTextInput.enterText(text);
      await tester.pump();
      // the same field with the focus after every letter
      expect(tester.state<EditableTextState>(field), same(editable), reason: text);
      expect(editable.widget.focusNode.hasFocus, isTrue, reason: text);
    }
    expect(state.problemName, 'Bottleneck');
    expect(state.problem!.name, 'Bottleneck');
  });
}
