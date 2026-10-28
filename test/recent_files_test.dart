/// Recent files: opened and saved files on the list (newest first, each once, at most ten), opened from the menu, a
/// file that is gone taken off the list - and a file passed at the start (opened in the Explorer or Finder).
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
  testWidgets('the list: newest first, each once, at most ten', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    expect(state.recentFiles, isEmpty);
    state.openScenario(Scenario.empty(), name: 'a.llab', path: '/x/a.llab');
    state.saved(name: 'b.llab', path: '/x/b.llab');
    state.openScenario(Scenario.empty(), name: 'a.llab', path: '/x/a.llab');
    state.openScenario(Scenario.empty(), name: 'brandenburg.llab'); // an example: no path
    expect(state.recentFiles, ['/x/a.llab', '/x/b.llab']);
    for (var i = 0; i < 12; i++) {
      state.saved(name: '$i.llab', path: '/x/$i.llab');
    }
    expect(state.recentFiles.length, AppState.maxRecentFiles);
    expect(state.recentFiles.first, '/x/11.llab');
    state.removeRecent('/x/11.llab');
    expect(state.recentFiles.first, '/x/10.llab');
    state.clearRecent();
    expect(state.recentFiles, isEmpty);
  });

  testWidgets('opened from the menu - a file that is gone taken off the list', (tester) async {
    MapView.showTiles = false;
    final dir = Directory.systemTemp.createTempSync('recent');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/brandenburg-kopie.llab')
      ..writeAsStringSync(File('assets/examples/brandenburg.llab').readAsStringSync());
    final gone = '${dir.path}/weg.llab';
    SharedPreferences.setMockInitialValues({
      'language': 'de',
      'recentFiles': [file.path, gone],
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.scenario.matrix['matrixSource'] = 'beeline';
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    Future<void> choose(String name) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zuletzt verwendet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      // the file is read
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await choose('brandenburg-kopie.llab');
    expect(state.fileName, 'brandenburg-kopie.llab');
    expect(state.filePath, file.path);
    expect(state.scenario.nodes, isNotEmpty);

    await choose('weg.llab');
    expect(find.textContaining('Die Datei gibt es nicht mehr'), findsOneWidget);
    expect(state.recentFiles, [file.path]);
    expect(state.fileName, 'brandenburg-kopie.llab');
  });

  testWidgets('a file passed at the start: opened once the window is shown', (tester) async {
    MapView.showTiles = false;
    final dir = Directory.systemTemp.createTempSync('start');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/doppelklick.llab')
      ..writeAsStringSync(File('assets/examples/brandenburg.llab').readAsStringSync());
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    await tester.pumpWidget(LogisticsLabApp(state: state, files: [file.path]));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(state.fileName, 'doppelklick.llab');
    expect(state.recentFiles, [file.path]);
  });
}
