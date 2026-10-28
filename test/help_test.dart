/// Help: the topics in all languages, the search (umlauts, accents, ranking), the help window from its button and F1.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/help/help.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/ui/map_view.dart';

HelpBook _book(String language) => HelpBook(language, [
  for (final t in jsonDecode(File('assets/help/$language.json').readAsStringSync()) as List)
    HelpTopic.fromJson(t as Map<String, dynamic>),
]);

void main() {
  test('the same topics in all languages', () {
    final ids = _book('de').topics.map((t) => t.id).toList();
    expect(ids.length, greaterThanOrEqualTo(10));
    for (final l in ['en', 'es', 'fr']) {
      expect(_book(l).topics.map((t) => t.id), ids, reason: l);
      for (final t in _book(l).topics) {
        expect(t.title, isNotEmpty);
        expect(t.body.length, greaterThan(100), reason: '$l ${t.id}');
      }
    }
  });

  test('search: umlauts and accents, title first, all words', () {
    final de = _book('de');
    expect(de.search('Lösung').first.topic.id, 'solution');
    expect(de.search('loesung').first.topic.id, 'solution');
    expect(de.search('losung').first.topic.id, 'solution');
    expect(de.search('Kante zeichnen').first.topic.id, 'network');
    expect(de.search('durchfahrt').first.topic.id, 'tsp');
    expect(de.search('xyz unbekannt'), isEmpty);
    expect(de.search('').length, de.topics.length);
    expect(de.search('deckungsbeitrag').first.snippet, contains('Deckungsbeitrag'));
    final fr = _book('fr');
    expect(fr.search('reseau').first.topic.id, 'network'); // réseau
    final es = _book('es');
    expect(es.search('camino mas corto').first.topic.id, 'shortestpath'); // más
  });

  testWidgets('help window from its button and with F1, search inside', (tester) async {
    MapView.showTiles = false;
    SharedPreferences.setMockInitialValues({'language': 'de'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(AppState.create))!;
    state.scenario.matrix['matrixSource'] = 'beeline';
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();

    // the help button next to the settings - no longer in the menu
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Hilfe'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100))); // the topics are loaded
    await tester.pumpAndSettle();
    expect(find.text('LogisticsLab Studio – Hilfe'), findsOneWidget);
    expect(find.text('Erste Schritte'), findsWidgets);

    // search: the network topic, its text on the right
    await tester.enterText(find.byType(TextField).last, 'Kante zeichnen');
    await tester.pump();
    expect(find.text('Netze und Kanten'), findsWidgets);
    expect(find.text('Erste Schritte'), findsNothing);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('LogisticsLab Studio – Hilfe'), findsNothing);

    // F1
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('LogisticsLab Studio – Hilfe'), findsOneWidget);
  });
}
