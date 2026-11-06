/// Data variants: the nodes and edges show and change the values of the variant of the chosen problem - in the file
/// only where they differ from the base.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('values per data variant, the base for the other problems', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    final s = Scenario.empty();
    final a = s.addNode(const LatLng(52.3, 13.6), roles: ['supplier'])..['supply'] = 100;
    s.addNode(const LatLng(52.4, 13.5), roles: ['transit'])['maxCap'] = 40;
    s.addNode(const LatLng(52.5, 13.4), roles: ['customer'])['demand'] = 80;
    final net = s.addNetwork('Netz', directed: false);
    net.addEdge('N1', 'N2')['capacity'] = 50;
    s.addProblem('mincostflow', 'Basis', {}).network = 'Netz';
    s.addProblem('multicommodity', 'Mehrgüter', {}).network = 'Netz';
    state.openScenario(s);
    expect(a.id, 'N1');

    // a new variant for the multi-commodity flow - a copy of the base
    state.problemName = 'Mehrgüter';
    state.newVariant('Mehrgüter');
    final id = state.problem!.variant!;
    expect(state.scenario.variantName(id), 'Mehrgüter');
    expect(state.scenario.node('N2')!['maxCap'], 40);
    expect(state.scenario.node('N2')!.differs('maxCap'), isFalse);

    // changed in the variant: only there
    state.edit(() {
      state.scenario.node('N2')!['maxCap'] = 1600;
      state.network!.edges.first['capacity'] = null; // unlimited
      state.scenario.node('N2')!.name = 'Umschlag'; // the name is the same in every variant
    });
    expect(state.scenario.node('N2')!['maxCap'], 1600);
    expect(state.scenario.node('N2')!.differs('maxCap'), isTrue);
    expect(state.network!.edges.first['capacity'], isNull);
    final json = state.scenario.json;
    final n2 = (json['nodes'] as List)[1] as Map;
    expect(n2['maxCap'], 40);
    expect(n2['variants'], {
      id: {'maxCap': 1600},
    });
    expect(n2['name'], 'Umschlag');

    // the other problem: the base values
    state.problemName = 'Basis';
    state.edit(() {});
    expect(state.scenario.node('N2')!['maxCap'], 40);
    expect(state.network!.edges.first['capacity'], 50);
    expect(state.scenario.node('N2')!.differs('maxCap'), isFalse);

    // back to the base value: nothing of the variant left at the node
    state.problemName = 'Mehrgüter';
    state.edit(() => state.scenario.node('N2')!.reset('maxCap'));
    expect(state.scenario.node('N2')!['maxCap'], 40);
    expect(n2.containsKey('variants'), isFalse);
    // the same value as the base: no own value
    state.edit(() => state.scenario.node('N1')!['supply'] = 100);
    expect(((json['nodes'] as List)[0] as Map).containsKey('variants'), isFalse);

    // a copy of a variant and deleting it: the problems use the base again
    state.newVariant('Kopie');
    final copy = state.problem!.variant!;
    expect(copy, isNot(id));
    expect(state.network!.edges.first['capacity'], isNull); // the value of the variant it was copied from
    state.deleteVariant(copy);
    expect(state.problem!.variant, isNull);
    expect(state.network!.edges.first['capacity'], 50);
    expect(state.scenario.variants.map((v) => v['id']), [id]);
  });

  testWidgets('solved with the values of the variant', skip: Platform.environment['LOGLAB_STDIO'] == null, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    final s = Scenario.empty();
    s.matrix['matrixSource'] = 'beeline';
    s.addNode(const LatLng(52.3, 13.6), roles: ['supplier'])['supply'] = 100;
    s.addNode(const LatLng(52.4, 13.5), roles: ['transit'])['maxCap'] = 40;
    s.addNode(const LatLng(52.5, 13.4), roles: ['customer'])['demand'] = 80;
    final net = s.addNetwork('Netz', directed: false);
    net.addEdge('N1', 'N2');
    net.addEdge('N2', 'N3');
    s.addProblem('mincostflow', 'Fluss', {}).network = 'Netz';
    state.openScenario(s);
    // the base: 40 through the transshipment node do not cover the demand of 80
    await tester.runAsync(state.solve);
    expect(state.solution!.status, 'noSolution');
    state.newVariant('Ausbau');
    state.edit(() => state.scenario.node('N2')!['maxCap'] = 100);
    await tester.runAsync(state.solve);
    expect(state.solution!.status, 'solution');
    expect(state.solution!.document['problem']['variant'], state.problem!.variant);
  });
}
