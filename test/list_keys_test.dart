/// Arrow keys up and down move through the list of the tab - not while typing in a field.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('arrow keys in the node, edge and connection lists', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    Future<void> key(LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pump();
    }

    // nodes: W, D1, D2, B ...
    state.selectNode('W');
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedNode, 'D1');
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedNode, 'D2');
    await key(LogicalKeyboardKey.arrowUp);
    expect(state.selectedNode, 'D1');

    // typing in the name field: the arrows stay there
    await tester.showKeyboard(find.widgetWithText(TextField, 'Lager Wildau'));
    await tester.pump();
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedNode, 'D1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // edges of the network of a min cost flow
    state.chooseProblem('Distribution über die Lager');
    state.setTab(DataTab.network);
    state.selectEdge(null);
    await tester.pump();
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedEdge, 0);
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedEdge, 1);

    // connections of a solution
    state.solutions[state.problemName!] = SolutionState({
      'status': 'solution',
      'results': {
        'objVal': 1,
        'edges': [
          {'from': 'W', 'to': 'D1', 'flow': 75, 'rate': 1},
          {'from': 'D1', 'to': 'B', 'flow': 40, 'rate': 1},
        ],
      },
    }, state.revision);
    state.setTab(DataTab.solution);
    await tester.pump();
    await key(LogicalKeyboardKey.arrowDown);
    expect(state.selectedFlow, 0);
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.arrowDown); // stays at the end
    expect(state.selectedFlow, 1);
  });

  testWidgets('enter in a field: the next input field, chips and buttons skipped', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // no routes
    state.selectNode('W');
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    EditableText? focused() =>
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>();

    // name -> the address below the role chips
    await tester.showKeyboard(find.widgetWithText(TextField, 'Werk Ludwigsfelde'));
    await tester.pump();
    final name = focused()!;
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final next = focused();
    expect(next, isNotNull);
    expect(next, isNot(same(name)));
    expect(next!.controller.text, isNot('Werk Ludwigsfelde'));
    // and on: again an input field
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(focused(), isNotNull);
    expect(focused(), isNot(same(next)));
  });
}
