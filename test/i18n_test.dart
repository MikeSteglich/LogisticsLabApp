/// Texts of all languages: every key of English, the same placeholders - and the app can show every language.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/i18n/strings.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/map_view.dart';

Map<String, String> _texts(String l) =>
    (jsonDecode(File('assets/i18n/$l.json').readAsStringSync()) as Map<String, dynamic>).cast<String, String>();

Set<String> _placeholders(String text) => {for (final m in RegExp(r'\{(\w+)\}').allMatches(text)) m.group(1)!};

void main() {
  final en = _texts('en');

  for (final l in supportedLanguages) {
    test('texts $l', () {
      final texts = _texts(l);
      expect(texts.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'keys not in English');
      expect(en.keys.toSet().difference(texts.keys.toSet()), isEmpty, reason: 'keys missing');
      for (final k in en.keys) {
        expect(_placeholders(texts[k]!), _placeholders(en[k]!), reason: '$l $k');
      }
      // the message keys of the modules (without the optional help texts)
      for (final k in allMessageKeys().where((k) => !k.endsWith('.help'))) {
        expect(texts.containsKey(k), isTrue, reason: '$l $k');
      }
    });
  }

  testWidgets('choice of the language', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Lösen'), findsOneWidget);

    for (final (code, name, solve) in [('es', 'Español', 'Resolver'), ('fr', 'Français', 'Résoudre')]) {
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      // the texts are loaded from the assets
      for (var i = 0; i < 20 && state.strings.language != code; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(state.strings.language, code);
      expect(find.text(solve), findsOneWidget);
      expect(find.text(code.toUpperCase()), findsOneWidget);
    }
    // numbers in the format of the language
    expect(state.strings.fixed(1234.5, 2), '1 234,50');
  });
}
