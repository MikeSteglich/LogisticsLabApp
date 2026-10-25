/// Lines of several tours on the same piece of road side by side - a tour there and back stays one line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';
import 'package:logisticslab_app/ui/theme.dart';

void main() {
  testWidgets('two tours over one crossing: side by side only there', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    // depot A, crossing X, customers B and C behind it
    final s = Scenario.empty();
    s.matrix['matrixSource'] = 'beeline';
    for (final (id, p) in const [
      ('A', LatLng(52.30, 13.30)),
      ('X', LatLng(52.35, 13.35)),
      ('B', LatLng(52.40, 13.30)),
      ('C', LatLng(52.40, 13.40)),
    ]) {
      s.addNode(p, roles: const []).json
        ..['id'] = id
        ..['name'] = id;
    }
    s.addProblem('vrp', 'Touren', {});
    state.openScenario(s);
    Map<String, dynamic> leg(String a, String b, String via) => {
      'from': a,
      'to': b,
      'value': 1,
      'path': [a, via, b],
    };
    void solution(List<List<Map<String, dynamic>>> tours) => state.solutions['Touren'] = SolutionState({
      'status': 'solution',
      'results': {
        'objVal': 1,
        'routes': [
          for (final (i, legs) in tours.indexed) {'vehicle': 'V${i + 1}', 'legs': legs},
        ],
      },
    }, state.revision);
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    int lines(Color c) => tester
        .widgetList<PolylineLayer<int>>(find.byType(PolylineLayer<int>))
        .expand((l) => l.polylines)
        .where((p) => p.color == c)
        .length;

    // one tour there and back over X: one line per section, no pieces
    solution([
      [leg('A', 'B', 'X'), leg('B', 'A', 'X')],
    ]);
    state.selectFlow(null);
    await tester.pump();
    expect(lines(Ui.accent), 2);

    // two tours: A-X shared - the sections split into the shared and the own piece
    solution([
      [leg('A', 'B', 'X'), leg('B', 'A', 'X')],
      [leg('A', 'C', 'X'), leg('C', 'A', 'X')],
    ]);
    state.selectFlow(null);
    await tester.pump();
    expect(lines(Ui.routeColors[0]), 4);
    expect(lines(Ui.routeColors[1]), 4);
  });
}
