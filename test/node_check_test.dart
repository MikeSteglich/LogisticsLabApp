/// Before solving: required values of the nodes (e.g. supply and demand of a tpp) and roles without nodes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/scenario.dart';

void main() {
  testWidgets('a tpp without supply and demand is not sent to the core', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    final s = Scenario.empty();
    s.addProblem('tpp', 'Transport', {});
    state.openScenario(s);
    state.scenario.matrix['matrixSource'] = 'beeline';

    // no nodes at all
    expect(state.nodeProblems, [
      'Keine Anbieter im Problem – im Knoten-Tab die Rolle vergeben',
      contains('Nachfrager'),
    ]);

    // nodes without values
    state.edit(() => state.scenario.addNode(const LatLng(52.3, 13.2), roles: ['supplier'])..json['name'] = 'Werk');
    state.edit(() => state.scenario.addNode(const LatLng(52.5, 13.4), roles: ['customer'])..json['name'] = 'Berlin');
    await tester.runAsync(state.solve);
    expect(state.lastResult, 'error');
    expect(state.message, contains('Angebot fehlt bei: Werk'));
    expect(state.message, contains('Nachfrage fehlt bei: Berlin'));

    // a wrong value
    state.edit(() {
      state.scenario.node('N1')!['supply'] = -5;
      state.scenario.node('N2')!['demand'] = 10;
    });
    expect(state.nodeProblems, ['Angebot ist ungültig bei: Werk']);
    state.edit(() => state.scenario.node('N1')!['supply'] = 10);
    expect(state.nodeProblems, isEmpty);
  });
}
