/// Renders the app with the example scenario, solves the TPP with the local solver and writes pictures of the app.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   LOGLAB_SHOTS=/tmp/shots flutter test test/screenshot_test.dart
///
/// Without LOGLAB_SHOTS the test is skipped. The map tiles are not loaded in tests (no network).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/help_dialog.dart';
import 'package:logisticslab_app/ui/main_screen.dart';
import 'package:logisticslab_app/ui/map_view.dart';

final shots = Platform.environment['LOGLAB_SHOTS'];

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/Users/mike/opt/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  testWidgets('screenshots', skip: shots == null, (tester) async {
    await tester.runAsync(loadFonts);
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': Platform.environment['LOGLAB_LANG'] ?? 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    final text = File('assets/examples/brandenburg.llab').readAsStringSync();
    state.openScenario(Scenario.parse(text), name: 'brandenburg.llab');

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: LogisticsLabApp(state: state),
      ),
    );
    await tester.pump();

    Future<void> shot(String name) async {
      await tester.pump();
      await tester.runAsync(() async {
        final r = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await r.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(shots!).createSync(recursive: true);
        File('$shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    // real time for the child process and the routing requests
    Future<void> settle(bool Function() done, {int seconds = 60}) async {
      for (var i = 0; i < seconds * 5 && !done(); i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    await shot('1-nodes');
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Über LogisticsLab Studio'));
    await tester.pumpAndSettle();
    await shot('0-about');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    state.selectNode('D1'); // roles only for other problems of the scenario
    await shot('1b-node-other-roles');
    state.selectNode('W');
    state.setNodeFilter('customer');
    await shot('1c-filter-customers');
    state.setNodeFilter(null);
    state.selectNode('W');

    await tester.runAsync(state.solve);
    await tester.pump();
    expect(state.message, isNull);
    expect(state.solution?.status, 'solution');
    // roads of the solution edges
    await settle(() => false, seconds: 8);
    await shot('2-solution');
    state.selectFlow(2); // Frankfurt (Oder) - orange on the map
    await shot('2b-solution-selected');
    state.selectFlow(null);

    state.setTab(DataTab.parameters);
    await shot('3-parameters');

    // network of the problem with all connections, one edge selected (the solver runs - roads are loaded)
    state.newNetwork('Direkt');
    state.addAllEdges();
    state.selectEdge(0);
    state.edit(() => state.edge!['capacity'] = 40);
    await settle(() => false, seconds: 6);
    await shot('5-network');

    // less supply than demand: Berlin gets only a part, Frankfurt and Cottbus nothing
    state.chooseNetwork(null);
    state.selectNode('B');
    state.edit(() => state.node!['demand'] = 120);
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('6-partial');

    // network flows: multimodal (split per mode), multi-stage WLP (open warehouses), commodities in the node mask
    state.edit(() => state.node!['demand'] = 40);
    state.chooseProblem('Lkw oder Bahn');
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('7-multimodal');
    state.chooseProblem('Lager mehrstufig');
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('8-multistagewlp');
    // min cost flow: utilization of the edges, the warehouses as transshipment nodes
    state.chooseProblem('Distribution über die Lager');
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('8b-utilization');
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    await shot('8b2-utilization-nodes');
    state.setTab(DataTab.nodes);
    state.setNodeFilter(AppState.transitFilter);
    await shot('8c-transit-filter');
    state.chooseProblem('Zwei Güter');
    state.selectNode('B');
    await shot('9-commodities');
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    state.setSolutionPart('parcels');
    await settle(() => false, seconds: 4);
    await shot('9b-commodity-parcels');
    state.setTab(DataTab.nodes);
    await shot('9c-nodes-parcels');
    state.setSolutionPart(null);
    // tsp: passage from the plant to Cottbus
    state.chooseProblem('Rundreise');
    state.edit(
      () => state.problem!.parameters
        ..['tourType'] = 'path'
        ..['startNode'] = 'W'
        ..['endNode'] = 'C',
    );
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('10-tsp-path');
    state.setTab(DataTab.parameters);
    await shot('10b-tsp-parameters');
    // shortest path in the network supply
    state.newProblem('shortestpath');
    state.chooseNetwork('supply');
    state.edit(
      () => state.problem!.parameters
        ..['startNode'] = 'W'
        ..['endNode'] = 'C',
    );
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('11-shortest-path');
    // chinese postman: the dead ends traversed twice - double lines
    state.newProblem('cpp');
    state.chooseNetwork('supply');
    state.edit(() {
      state.network!.directed = false;
      state.problem!.parameters['startNode'] = 'W';
    });
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('13-cpp');
    // vehicle routing: two tours in their colours, the schedule
    state.chooseProblem('Touren ab Wildau');
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    await settle(() => false, seconds: 4);
    await shot('14-vrp');
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    await shot('14a-vrp-tables');
    // fixed start: waiting at the customers - in the wide view
    state.edit(() => state.problem!.parameters['fixedStart'] = true);
    await tester.runAsync(state.solve);
    state.setTab(DataTab.solution);
    state.toggleWideData();
    await settle(() => false, seconds: 3);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    await shot('14d-vrp-wide');
    // a tour of the overview highlighted on the map
    await tester.tap(find.descendant(of: find.byType(Table), matching: find.text('Tour 2 · LKW2')).first);
    await shot('14f-vrp-route');
    state.selectRoute(null);
    // while solving: the cancel button
    state.status = 'running';
    state.notifyListeners();
    await shot('14e-solving');
    state.status = null;
    state.notifyListeners();
    state.toggleWideData();
    state.edit(() => state.problem!.parameters.remove('fixedStart'));
    state.setTab(DataTab.nodes);
    state.selectNode('B');
    await tester.pump();
    await shot('14b-vrp-customer');
    state.setTab(DataTab.parameters);
    await tester.pump();
    await shot('14c-vrp-parameters');
    // warehouse location: the open candidates, the assignments
    state.chooseProblem('Lagerstandorte (WLP)');
    await tester.runAsync(state.solve);
    await tester.pump();
    await settle(() => false, seconds: 3);
    await shot('16-wlp');
    state.tapNode('D1');
    await shot('16a-wlp-location');
    state.highlightNode(null);
    // continuous location: the locations found anywhere on the map
    state.chooseProblem('Freie Standorte (CLP, p-Median)');
    await tester.runAsync(state.solve);
    await tester.pump();
    await settle(() => false, seconds: 3);
    await shot('17-clp');
    // pickup and delivery: the requests as dashed lines, the tours with the load
    state.chooseProblem('Abholen und Zustellen');
    state.setTab(DataTab.nodes);
    state.selectNode('W');
    await tester.pump();
    await shot('15-pdp-nodes');
    state.selectNode('B');
    await tester.pump();
    await shot('15b-pdp-delivery');
    await tester.runAsync(state.solve);
    await tester.pump();
    await settle(() => false, seconds: 4);
    state.toggleWideData();
    await tester.pump();
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    await shot('15a-pdp-solution');
    state.toggleWideData();
    // help window with a search
    showHelp(tester.element(find.byType(MainScreen)), state, query: 'Rundreise');
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await shot('12-help');
    Navigator.of(tester.element(find.byType(MainScreen))).pop();
    await tester.pumpAndSettle();
    state.chooseProblem('Transport direkt vom Werk');

    tester.view.physicalSize = const Size(820, 1180); // tablet portrait
    await tester.pump();
    state.setTab(DataTab.nodes);
    await shot('4-tablet');

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
