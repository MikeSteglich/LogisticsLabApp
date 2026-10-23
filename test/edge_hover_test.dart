/// Mouse over an edge: a card with its values; a click selects it (solution or network tab).
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('hover and click on edges', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline'; // straight lines
    state.solutions[state.problemName!] = SolutionState({
      'status': 'solution',
      'results': {
        'objVal': 100,
        'summary': {'totalCosts': 100},
        'assignments': [
          {'from': 'W', 'to': 'B', 'flow': 40, 'rate': 1.5},
          {'from': 'W', 'to': 'F', 'flow': 20, 'rate': 2.25},
        ],
      },
    }, state.revision);
    state.newNetwork('Direkt');
    state.addEdge('W', 'D2'); // edge without flow
    state.selectEdge(null);
    state.setTab(DataTab.nodes);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    state.geometry++;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final camera = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;
    final origin = tester.getTopLeft(find.byType(FlutterMap));
    // screen point at 40 % of the straight line a -> b (away from the node symbols)
    Offset on(String a, String b) {
      final p = state.scenario.node(a)!.position, q = state.scenario.node(b)!.position;
      final m = LatLng(p.latitude + 0.4 * (q.latitude - p.latitude), p.longitude + 0.4 * (q.longitude - p.longitude));
      return origin + camera.latLngToScreenOffset(m);
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    // connection of the solution
    await mouse.moveTo(on('W', 'F'));
    await tester.pump();
    expect(find.text('Werk Ludwigsfelde → Frankfurt (Oder)'), findsOneWidget);
    expect(find.textContaining('Menge 20'), findsOneWidget);
    await tester.tapAt(on('W', 'F'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 500)); // the map waits whether a double click follows
    await tester.pump();
    expect(state.selectedFlow, 1);
    expect(state.tab, DataTab.solution);

    // edge of the network without flow
    await mouse.moveTo(on('W', 'D2'));
    await tester.pump();
    expect(find.text('Werk Ludwigsfelde → Lager Brandenburg'), findsOneWidget);
    expect(find.textContaining('Kapazität –'), findsOneWidget);
    await tester.tapAt(on('W', 'D2'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(state.selectedEdge, 0);
    expect(state.tab, DataTab.network);

    // beside the lines: no card
    await mouse.moveTo(origin + const Offset(20, 450));
    await tester.pump();
    expect(find.textContaining('Kapazität –'), findsNothing); // only the card has this text
  });
}
