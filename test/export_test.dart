/// The solution as Excel file: the sheets of every group of problems, numbers as numbers, names instead of ids.
///
///   LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
///   flutter test test/export_test.dart          (LOGLAB_EXPORT_DIR: the files are also written there)
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/backend/backend.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/model/solution_export.dart';
import 'package:logisticslab_app/model/xlsx.dart';

final _stdio = Platform.environment['LOGLAB_STDIO'] == null;

/// the file read back: sheet name -> rows of cell texts (numbers as their XML text)
Map<String, List<List<String>>> _read(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String file(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
  final names = RegExp(r'<sheet name="([^"]*)"').allMatches(file('xl/workbook.xml')).map((m) => m.group(1)!).toList();
  return {
    for (final (i, n) in names.indexed)
      n: [
        for (final row in RegExp(r'<row [^>]*>(.*?)</row>').allMatches(file('xl/worksheets/sheet${i + 1}.xml')))
          [
            for (final c in RegExp(
              r'<c r="[A-Z]+\d+"[^>]*>(?:<v>([^<]*)</v>|<is><t[^>]*>([^<]*)</t></is>)</c>',
            ).allMatches(row.group(1)!))
              c.group(1) ?? c.group(2)!,
          ],
      ],
  };
}

void main() {
  test('the writer: texts escaped, numbers as numbers, sheet names valid and unique', () {
    final a = XlsxSheet('Touren: A/B')..add(['Name', 'Wert'], bold: true);
    a.add(['<Müller & Söhne>', 12.5]);
    a.add(['ganz', 3]);
    final b = XlsxSheet('Touren: A/B')..add(['x']);
    final bytes = encodeXlsx([a, b, XlsxSheet('leer')]);
    final zip = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('&lt;Müller &amp; Söhne&gt;'));
    expect(sheet, contains('<c r="B2" s="2"><v>12.5</v></c>')); // shown with two decimals
    expect(sheet, contains('<c r="B3"><v>3</v></c>'));
    expect(sheet, contains('<c r="A1" s="1" t="inlineStr">')); // bold header
    expect(_read(bytes).keys, ['Touren  A B', 'Touren  A B 2']); // the empty sheet left out
  });

  testWidgets('the sheets of transport, routing, pickup and delivery and location problems', skip: _stdio, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    state.openScenario(Scenario.parse(File('assets/examples/brandenburg.llab').readAsStringSync()));
    state.scenario.matrix['matrixSource'] = 'beeline';
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
    final dir = Platform.environment['LOGLAB_EXPORT_DIR'];
    // the sheets and a column with names of nodes
    for (final (problem, sheets, (names, column)) in [
      ('Transport direkt vom Werk', ['Übersicht', 'Verbindungen', 'Knoten'], ('Verbindungen', 0)),
      ('Touren ab Wildau', ['Übersicht', 'Touren', 'Teilstücke'], ('Teilstücke', 2)),
      ('Abholen und Zustellen', ['Übersicht', 'Touren', 'Teilstücke', 'Fahrten'], ('Fahrten', 0)),
      ('Lagerstandorte (WLP)', ['Übersicht', 'Standorte', 'Zuordnung der Kunden'], ('Zuordnung der Kunden', 1)),
      (
        'Freie Standorte (CLP, p-Median)',
        ['Übersicht', 'Standorte', 'Zuordnung der Kunden'],
        ('Zuordnung der Kunden', 1),
      ),
    ]) {
      state.chooseProblem(problem);
      await tester.runAsync(state.solve);
      expect(state.message, isNull, reason: problem);
      final bytes = solutionXlsx(state);
      if (dir != null) File('$dir/$problem.xlsx').writeAsBytesSync(bytes);
      final book = _read(bytes);
      expect(book.keys, sheets, reason: problem);
      // the overview: the problem and the objective with its value as a number
      final overview = book['Übersicht']!;
      expect(overview.first, ['Problem', problem]);
      final objective = overview.firstWhere((r) => r.isNotEmpty && r.first.endsWith('(Zielfunktion)'));
      expect(num.parse(objective[1]), closeTo(state.solution!.results!['objVal'] as num, 0.01), reason: problem);
      // names instead of ids, a row per connection, section or assignment
      final rows = book[names]!.skip(1).toList();
      expect(rows, isNotEmpty, reason: problem);
      final nodeNames = {for (final n in state.scenario.nodes) n.name};
      expect(rows.every((r) => nodeNames.contains(r[column])), isTrue, reason: '$problem: ${rows.first}');
    }
    await tester.runAsync(() => state.setBackendSettings(defaultBackendSettings()));
  });
}
