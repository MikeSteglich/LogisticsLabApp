/// A solver that hangs does not block the app: cancelling the busy dialog drops the result, resetting the
/// backend stops the solver and the waiting request ends with an error.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/ui/messages.dart';

void main() {
  testWidgets('busy dialog can be cancelled', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final work = Completer<String>();
    var cancelled = false;
    final result = busy(
      ctx,
      'Importiere …',
      () => work.future,
      cancelLabel: 'Abbrechen',
      onCancel: () => cancelled = true,
    );
    await tester.pump();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(cancelled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    work.complete('zu spät'); // dropped - no error, no dialog
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('hanging solver is stopped', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    final python = Platform.isWindows ? 'python' : 'python3';
    await tester.runAsync(
      () => state.setBackendSettings(
        BackendSettings(executable: python, arguments: ['${Directory.current.path}/test/fixtures/hanging_core.py']),
      ),
    );
    await tester.runAsync(() async {
      Object? error;
      final request = state
          .convertOld('x.TPPX', 'TPPX')
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      await Future.delayed(const Duration(seconds: 1));
      expect(error, isNull); // still waiting - the solver does not answer
      final watch = Stopwatch()..start();
      await state.resetBackend();
      await request.timeout(const Duration(seconds: 20));
      expect(error, isA<BackendException>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
