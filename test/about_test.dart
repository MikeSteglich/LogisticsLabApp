/// About dialog: the version is the one of pubspec.yaml, the credits and the thanks are shown.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/ui/about_dialog.dart';
import 'package:logisticslab_app/ui/map_view.dart';

void main() {
  test('version as in pubspec.yaml', () {
    final m = RegExp(
      r'^version:\s*([0-9][^+\s]*)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(appVersion, m!.group(1));
  });

  testWidgets('about dialog from the menu', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();

    // on the map only the attribution of OpenStreetMap
    expect(find.text('© OpenStreetMap-Mitwirkende'), findsOneWidget);
    expect(find.textContaining('flutter_map'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Über LogisticsLab Studio'));
    await tester.pumpAndSettle();
    expect(find.text('Version $appVersion'), findsOneWidget);
    expect(find.textContaining('openrouteservice'), findsOneWidget);
    expect(find.textContaining('Photon (komoot)'), findsOneWidget);
    expect(find.textContaining('Katrin Kampe'), findsOneWidget);
    expect(find.textContaining('LogisticsLab 5'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Version $appVersion'), findsNothing);
  });
}
