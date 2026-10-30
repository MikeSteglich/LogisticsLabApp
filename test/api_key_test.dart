/// A server with API keys: the app asks for the key when the server refuses it (401), sends it and asks again if
/// it is wrong - a small server in the test answers like the LogisticsLab server.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  testWidgets('the API key asked for, sent and asked again if refused', (tester) async {
    HttpOverrides.global = null; // real requests to the server of the test (flutter_test answers them with 400)
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // every request refused - the keys it got noted
    final keys = <String?>[];
    final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      keys.add(r.headers.value('X-API-Key'));
      await r.drain<void>();
      r.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'message': 'invalid api key'}));
      await r.response.close();
    });

    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(
      () => state.setBackendSettings(
        defaultBackendSettings().copyWith(remote: true, url: 'http://127.0.0.1:${server.port}/v1/', apiKey: ''),
      ),
    );
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    // the old dialog closed, the request answered, the new dialog shown (the spinner of solving never settles)
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 60 && (state.solving || find.byType(AlertDialog).evaluate().isEmpty); i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    // without a key: refused - the app asks for it
    await tester.tap(find.text('Lösen'));
    await settle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('API-Key'), findsWidgets); // title and label of the field
    expect(find.textContaining('Der Server verlangt einen API-Key'), findsOneWidget);
    expect(keys.last, isNull);

    // a wrong key: sent, refused again - the app says so
    await tester.enterText(find.byType(TextField).last, 'falsch');
    await tester.tap(find.text('Übernehmen und lösen'));
    await settle();
    expect(state.backendSettings.apiKey, 'falsch');
    expect(keys.last, 'falsch');
    expect(find.textContaining('nicht angenommen'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.lastResult, 'apiKey');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });
}
