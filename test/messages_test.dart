/// Errors stay until they are closed, the busy dialog blocks the app while the work runs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/ui/messages.dart';

void main() {
  testWidgets('error dialog and busy dialog', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
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

    // error: still there after 30 s, gone after closing
    unawaited(showError(ctx, state.strings, 'kaputt.TPPX kann nicht importiert werden'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('kaputt.TPPX kann nicht importiert werden'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // busy: shown while the work runs, a tap beside it does not close it
    final work = Completer<int>();
    final result = busy(ctx, 'Importiere drogma.CLPX …', () => work.future);
    await tester.pump();
    expect(find.text('Importiere drogma.CLPX …'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Importiere drogma.CLPX …'), findsOneWidget);
    work.complete(42);
    await tester.pump(const Duration(seconds: 1)); // the dialog stays at least 0.6 s
    expect(await result, 42);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // a fast step: the dialog is still seen (at least 0.6 s)
    final fast = busy(ctx, 'Importiere schnell …', () async => 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Importiere schnell …'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Importiere schnell …'), findsNothing);
    expect(await fast, 1);

    // old formats of LogisticsLab 4 are recognised by the app
    expect(AppState.legacyFormats, contains('TPP'));
    expect(AppState.isOldFile('drogma.CLPX'), isTrue);
  });
}
