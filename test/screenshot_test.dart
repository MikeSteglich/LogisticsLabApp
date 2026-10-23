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

    await tester.runAsync(state.solve);
    await tester.pump();
    expect(state.message, isNull);
    expect(state.solution?.status, 'solution');
    // roads of the solution edges
    await settle(() => false, seconds: 8);
    await shot('2-solution');

    state.setTab(DataTab.parameters);
    await shot('3-parameters');

    tester.view.physicalSize = const Size(820, 1180); // tablet portrait
    await tester.pump();
    state.setTab(DataTab.nodes);
    await shot('4-tablet');

    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings())); // stops the solver
  });
}
