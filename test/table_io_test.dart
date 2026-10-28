/// Copy and paste of tables: the text of Excel, numbers in both formats, nodes and edges there and back, the
/// errors of a paste, the solution as table - and the coordinates of pasted addresses (with the local solver).
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/table_io_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/main.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/model/table_io.dart';
import 'package:logisticslab_app/model/table_text.dart';
import 'package:logisticslab_app/ui/map_view.dart';

final _stdio = Platform.environment['LOGLAB_STDIO'] == null;

Future<AppState> _state(WidgetTester tester, String problem) async {
  SharedPreferences.setMockInitialValues({'language': 'de'});
  final state = (await tester.runAsync(AppState.create))!;
  state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
  state.scenario.matrix['matrixSource'] = 'beeline';
  state.chooseProblem(problem);
  return state;
}

void main() {
  test('the text of Excel: tabs, quoted cells with line breaks, CSV with semicolons', () {
    expect(parseTable('Name\tBedarf\r\nBerlin\t40\r\n"Frankfurt\n(Oder)"\t"2""0"\r\n\r\n'), [
      ['Name', 'Bedarf'],
      ['Berlin', '40'],
      ['Frankfurt\n(Oder)', '2"0'],
    ]);
    expect(parseTable('Name;Breite\nBerlin;52,52'), [
      ['Name', 'Breite'],
      ['Berlin', '52,52'],
    ]);
    expect(parseTable('a\tb\nc'), [
      ['a', 'b'],
      ['c', ''],
    ]);
    // and back: Excel takes the quoted cell as one
    expect(
      tableText([
        ['a', 'b\nc'],
      ]),
      'a\t"b\nc"\n',
    );
  });

  test('numbers with decimal comma or point, thousands, units', () {
    expect(parseNumber('52,52'), 52.52);
    expect(parseNumber('1.234,5'), 1234.5);
    expect(parseNumber('1.234'), 1234);
    expect(parseNumber('1.234', decimalComma: false), 1.234);
    expect(parseNumber('1,234', decimalComma: false), 1234);
    expect(parseNumber('52.52'), 52.52);
    expect(parseNumber('40 km'), 40);
    expect(parseNumber('−3'), -3);
    expect(parseNumber('83 %'), 83);
    expect(parseNumber('abc'), isNull);
    expect(parseNumber(''), isNull);
  });

  testWidgets('nodes to Excel and back: the headers recognised, the existing nodes updated', (tester) async {
    final state = await _state(tester, 'Transport direkt vom Werk');
    final text = copyTable(state, TableKind.nodes);
    final rows = parseTable(text);
    expect(rows.first, ['Name', 'ID', 'Breite', 'Länge', 'Rollen', 'aktiv', 'Angebot', 'Nachfrage', 'Kostenfaktor']);
    expect(rows.length, state.filteredNodes.length + 1);
    // in Excel: a new demand for Berlin
    final berlin = rows.indexWhere((r) => r.first == 'Berlin');
    final demand = rows.first.indexOf('Nachfrage');
    rows[berlin][demand] = '55,5';
    final paste = TableImport(state, TableKind.nodes, tableText(rows));
    expect(paste.header, isTrue);
    expect(paste.mode, ImportMode.update); // all names known
    final check = paste.check();
    expect(check.errors, isEmpty);
    expect((check.added, check.updated), (0, rows.length - 1));
    await tester.runAsync(paste.apply);
    expect(state.scenario.node('B')!['demand'], 55.5);
    // nothing else changed: copied again the same text but the demand
    expect(parseTable(copyTable(state, TableKind.nodes))[berlin][demand], '55,5');
  });

  testWidgets('new nodes without a header and with errors in some rows', (tester) async {
    final state = await _state(tester, 'Touren ab Wildau');
    final before = state.scenario.nodes.length;
    // without a header: name, latitude and longitude from the values
    final plain = TableImport(state, TableKind.nodes, 'Eberswalde\t52,83\t13,82\nPrenzlau\t53,32\t13,86\n');
    expect(plain.header, isFalse);
    expect(plain.mapping, ['name', 'latitude', 'longitude']);
    expect(plain.role, 'customer');
    await tester.runAsync(plain.apply);
    expect(state.scenario.nodes.length, before + 2);
    final e = state.scenario.nodes.firstWhere((n) => n.name == 'Eberswalde');
    expect(e.position.latitude, 52.83);
    expect(e.roles, ['customer']);

    // with a header: one good row, the others with errors - their rows as in Excel
    final paste = TableImport(
      state,
      TableKind.nodes,
      'Name\tBreite\tLänge\tRollen\tBedarf\tZeitfenster\n'
      'Templin\t53,12\t13,5\tNachfrager\t12\t08:00–12:00\n'
      'Schwedt\tx\t14,28\tNachfrager\t5\t\n'
      'Angermünde\t53,02\t14,0\tKunde\t5\t\n'
      'Bernau\t\t\t\t3\t\n',
    );
    expect(paste.mode, ImportMode.add);
    final check = paste.check();
    expect(check.added, 1);
    expect(
      [for (final e in check.errors) (e.row, e.key)],
      [(3, 'ui.import.noCoordinate'), (4, 'ui.import.noRole'), (5, 'ui.import.noPosition')],
    );
    await tester.runAsync(paste.apply);
    final templin = state.scenario.nodes.firstWhere((n) => n.name == 'Templin');
    expect(templin['demand'], 12);
    expect(templin['timeWindow'], [480, 720]);
  });

  testWidgets('names and postal codes without an address: the address made of their columns', (tester) async {
    final state = await _state(tester, 'Touren ab Wildau');
    final paste = TableImport(state, TableKind.nodes, 'Name\tPost code\nBestensee\t15741\nMittenwalde\t15749\n');
    expect(paste.header, isTrue);
    expect(paste.mapping, ['name', null]);
    expect(paste.addressParts, [0, 1]);
    expect(paste.columnName(1), 'Post code');
    expect(paste.check().toLocate, [(2, 'Bestensee, 15741'), (3, 'Mittenwalde, 15749')]);
    // street and place: the name is no part of the address; a column named otherwise is none
    final full = TableImport(
      state,
      TableKind.nodes,
      'Name\tStraße\tPLZ\tOrt\tBemerkung\nLager\tHochschulring 1\t15745\tWildau\tneu\n',
    );
    expect(full.mapping, ['name', null, null, null, null]);
    expect(full.check().toLocate.single.$2, 'Hochschulring 1, 15745, Wildau');
    // without a header: the name and all other columns; with coordinates no address
    expect(TableImport(state, TableKind.nodes, 'Bestensee\t15741\nHalbe\t15757\n').addressParts, [0, 1]);
    expect(TableImport(state, TableKind.nodes, 'Eberswalde\t52,83\t13,82\n').addressParts, isEmpty);
    // chosen in the dialog: only the name
    paste.addressParts = [0];
    expect(paste.check().toLocate.first.$2, 'Bestensee');
  });

  testWidgets('a network flow: the roles from supply and demand, transshipment nodes, their capacity', (tester) async {
    final state = await _state(tester, 'Distribution über die Lager');
    expect(state.assignableRoles, contains('transit'));
    final paste = TableImport(
      state,
      TableKind.nodes,
      'Name\tBreite\tLänge\tAngebot\tNachfrage\tKapazität\n'
      'Werk Süd\t51,9\t14,3\t500\t0\t450\n'
      'Laden Nord\t53,0\t13,9\t\t40\t\n'
      'Umschlag Mitte\t52,4\t13,6\t0\t0\t300\n',
    );
    expect(paste.mapping, ['name', 'latitude', 'longitude', 'supply', 'demand', 'maxCap']);
    expect(paste.role, TableImport.autoRole);
    await tester.runAsync(paste.apply);
    Node node(String name) => state.scenario.nodes.firstWhere((n) => n.name == name);
    expect(node('Werk Süd').roles, ['supplier']);
    expect(node('Laden Nord').roles, ['customer']);
    expect(node('Umschlag Mitte').roles, ['transit']);
    expect(node('Umschlag Mitte')['maxCap'], 300);
    expect(node('Werk Süd')['maxCap'], isNull); // the throughput only of transshipment nodes
    expect(state.isTransit(node('Umschlag Mitte')), isTrue); // not yet in the network
    // one role for all
    final one = TableImport(state, TableKind.nodes, 'Name\tBreite\tLänge\tAngebot\nWerk West\t52,0\t12,0\t50\n');
    one.role = 'transit';
    await tester.runAsync(one.apply);
    expect(node('Werk West').roles, ['transit']);
  });

  testWidgets('the dialog of a paste: text pasted, columns shown, applied', (tester) async {
    MapView.showTiles = false;
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester, 'Transport direkt vom Werk');
    state.tab = DataTab.nodes;
    await tester.pumpWidget(LogisticsLabApp(state: state));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.table_view_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Knoten einfügen (aus Excel) …'));
    // the clipboard is read
    for (var i = 0; i < 10 && find.byType(AlertDialog).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Knoten einfügen (aus Excel) …'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'Name\tBreite\tLänge\tNachfrage\nEberswalde\t52,83\t13,82\t7\n',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 neu, 0 aktualisiert'), findsOneWidget);
    expect(find.text('Nachfrage'), findsWidgets); // the meaning of the column
    await tester.tap(find.text('Übernehmen'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Knoten einfügen (aus Excel) …'), findsNothing);
    expect(state.scenario.nodes.firstWhere((n) => n.name == 'Eberswalde')['demand'], 7);
  });

  testWidgets('edges to Excel and back, unknown nodes reported', (tester) async {
    final state = await _state(tester, 'Distribution über die Lager');
    final net = state.network!;
    final rows = parseTable(copyTable(state, TableKind.edges));
    expect(rows.first.take(3), ['Von', 'Nach', 'gerichtet']);
    expect(rows.length, net.edges.length + 1);
    // all edges again: they exist already
    final again = TableImport(state, TableKind.edges, tableText(rows)).check();
    expect(again.added, 0);
    expect(again.errors.every((e) => e.key == 'ui.import.edgeExists'), isTrue);
    final paste = TableImport(state, TableKind.edges, 'Von\tNach\nCottbus\tBerlin\nCottbus\tNirgendwo\n');
    final check = paste.check();
    expect((check.added, check.errors.single.key), (1, 'ui.import.unknownNode'));
    final n = net.edges.length;
    await tester.runAsync(paste.apply);
    expect(state.network!.edges.length, n + 1);
  });

  testWidgets('edges of a min cost flow: capacity and fixed costs there and back, headers in the plural', (
    tester,
  ) async {
    final state = await _state(tester, 'Distribution über die Lager');
    state.chooseProblem(state.scenario.problems.firstWhere((p) => p.type == 'mincostflow').name);
    // the fixed costs only if the problem uses them - as in the mask
    state.edit(() => state.problem!.parameters['useFixedCosts'] = false);
    final edges = state.network!.edges;
    edges[0]['capacity'] = 120;
    edges[0]['fixedCost'] = 35;
    expect(parseTable(copyTable(state, TableKind.edges)).first, isNot(contains('Fixkosten')));
    state.edit(() => state.problem!.parameters['useFixedCosts'] = true);
    final rows = parseTable(copyTable(state, TableKind.edges));
    expect(rows.first, containsAll(['Kapazität', 'Fixkosten']));
    expect(rows[1][rows.first.indexOf('Kapazität')], '120');
    expect(rows[1][rows.first.indexOf('Fixkosten')], '35');
    // updated with Kapazitäten (plural)
    final from = state.nameOf(edges[0].from), to = state.nameOf(edges[0].to);
    final paste = TableImport(state, TableKind.edges, 'Von\tNach\tKapazitäten\tFixkosten\n$from\t$to\t150\t40\n');
    expect(paste.mapping, ['from', 'to', 'capacity', 'fixedCost']);
    paste.mode = ImportMode.update;
    await tester.runAsync(paste.apply);
    expect((edges[0]['capacity'], edges[0]['fixedCost']), (150, 40));
  });

  testWidgets('the solution as table for Excel: its sheets one below the other', skip: _stdio, (tester) async {
    final state = await _state(tester, 'Transport direkt vom Werk');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    await tester.runAsync(state.solve);
    final rows = parseTable(copySolution(state));
    expect(rows.first.first, 'Übersicht');
    expect(rows.any((r) => r.first == 'Verbindungen'), isTrue);
    expect(rows.any((r) => r.first == 'Werk Ludwigsfelde' && r[1] == 'Berlin' && r[2] == '40'), isTrue);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });

  testWidgets('pasted addresses without coordinates: looked up', skip: _stdio, (tester) async {
    final state = await _state(tester, 'Transport direkt vom Werk');
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    final paste = TableImport(
      state,
      TableKind.nodes,
      'Name\tAdresse\tBedarf\nTH Wildau\tHochschulring 1, Wildau\t5\nNirgendwo\tXyzqw 99999 Unbekannt\t1\n',
    );
    final check = paste.check();
    expect(check.toLocate.length, 2);
    final result = (await tester.runAsync(paste.apply))!;
    expect(result.added, 1);
    expect(result.errors.single.key, 'ui.import.addressNotFound');
    final wildau = state.scenario.nodes.firstWhere((n) => n.name == 'TH Wildau');
    expect(wildau.position.latitude, closeTo(52.32, 0.05));
    expect(wildau.position.longitude, closeTo(13.63, 0.05));
    // names and postal codes: the address made of both
    final plain = TableImport(state, TableKind.nodes, 'Name\tPost code\nBestensee\t15741\nGroß Köris\t15746\n');
    expect((await tester.runAsync(plain.apply))!.added, 2);
    final bestensee = state.scenario.nodes.firstWhere((n) => n.name == 'Bestensee');
    expect(bestensee.address, 'Bestensee, 15741');
    expect(bestensee.position.latitude, closeTo(52.24, 0.05));
    expect(bestensee.position.longitude, closeTo(13.65, 0.05));
    // all nodes of the list with an address: looked up again
    final (found, missing) = (await tester.runAsync(() => locateNodes(state, [wildau])))!;
    expect(found, 1);
    expect(missing, isEmpty);
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });
}
