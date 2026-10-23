/// Import of an old LogisticsLab file (TPPX) - converted by the local solver, then solved.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/import_test.dart
///
/// Without LOGLAB_STDIO the test is skipped. Solving needs network (OSM) if the file uses road distances.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';

void main() {
  testWidgets('import old file', skip: Platform.environment['LOGLAB_STDIO'] == null, (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));

    const name = 'Baukies-angebotsueberschuss.TPPX';
    expect(AppState.isOldFile(name), isTrue);
    expect(AppState.isOldFile('brandenburg.llab'), isFalse);
    final bytes = File('test/fixtures/$name').readAsBytesSync();
    final text = () {
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    }();

    await tester.runAsync(() => state.importOld(name, text));
    expect(state.fileName, 'Baukies-angebotsueberschuss.tppx.llab');
    expect(state.filePath, isNull); // Save asks for the place
    expect(state.dirty, isTrue);
    expect(state.scenario.nodes, isNotEmpty);
    expect(state.problem?.type, 'tpp');

    await tester.runAsync(state.solve);
    expect(state.message, isNull);
    expect(state.solution?.status, 'solution');

    // broken file: clear message, the open scenario stays
    Object? error;
    await tester.runAsync(() async {
      try {
        await state.importOld('kaputt.TPPX', 'TPPX 1.0\nOPTIONS\nSOURCES\nkeine Zahl');
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<BackendException>());
    expect(state.fileName, 'Baukies-angebotsueberschuss.tppx.llab');

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
