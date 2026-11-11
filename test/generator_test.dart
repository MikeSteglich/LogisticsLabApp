/// Random problems: cities of the region, the values around the means - the same start value gives the same problem,
/// every problem type without missing values.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logisticslab_app/app_state.dart';
import 'package:logisticslab_app/model/generator.dart';
import 'package:logisticslab_app/model/scenario.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/generator_dialog.dart';
import 'package:flutter/material.dart';

void main() {
  final cities = parseCities(File('assets/data/cities.tsv').readAsStringSync());

  GeneratorSettings settings(String type, {int seed = 1, Set<String> countries = const {'DE'}}) {
    final plan = GeneratorPlan.of(modules[type]!);
    return GeneratorSettings(
      type: type,
      countries: countries,
      counts: {for (final g in plan.groups) g.key: plan.defaultCount(g)},
      means: {
        for (final g in plan.groups)
          for (final f in g.fields)
            if (plan.defaultMean(f) != null) '${g.key}.${f.key}': plan.defaultMean(f),
        for (final f in plan.edgeFields)
          if (plan.defaultMean(f) != null) 'edge.${f.key}': plan.defaultMean(f),
      },
      costPerKm: 1,
      seed: seed,
    );
  }

  test('the cities of Europe', () {
    expect(cities.length, greaterThan(13000));
    expect(cities.where((c) => c.name == 'Wildau' && c.country == 'DE'), hasLength(1));
  });

  test('the same start value gives the same problem, another one another', () {
    String text(int seed) => generate(
      settings('tpp', seed: seed),
      cities,
      name: 'S',
      problemName: 'P',
      networkName: 'N',
    ).toText();
    expect(text(7), text(7));
    expect(text(7), isNot(text(8)));
  });

  test('transport problem: the cities in Germany, apart, the supply covers the demand', () {
    final s = generate(settings('tpp'), cities, name: 'S', problemName: 'P', networkName: 'N');
    final german = {for (final c in cities.where((c) => c.country == 'DE')) c.name};
    expect(s.nodes, hasLength(11));
    expect(s.nodes.every((n) => german.contains(n.name)), isTrue);
    final supply = s.nodes.fold<num>(0, (t, n) => t + ((n['supply'] as num?) ?? 0));
    final demand = s.nodes.fold<num>(0, (t, n) => t + ((n['demand'] as num?) ?? 0));
    expect(supply, greaterThanOrEqualTo(demand));
    for (final n in s.nodes.where((n) => n.roles.contains('customer'))) {
      expect(n['demand'] as num, inInclusiveRange(21, 39)); // 30 ± 30 %
    }
    const d = Distance();
    for (final a in s.nodes) {
      for (final b in s.nodes.where((b) => b.id != a.id)) {
        expect(d.as(LengthUnit.Kilometer, a.position, b.position), greaterThan(20));
      }
    }
  });

  test('a section of the map: only the cities in it', () {
    final g = settings('tsp');
    final s = generate(
      GeneratorSettings(
        type: 'tsp',
        countries: const {},
        section: (const LatLng(52.0, 12.8), const LatLng(52.8, 14.0)), // around Berlin
        counts: g.counts,
        seed: 3,
      ),
      cities,
      name: 'S',
      problemName: 'P',
      networkName: 'N',
    );
    expect(s.nodes, hasLength(10));
    for (final n in s.nodes) {
      expect(n.position.latitude, inInclusiveRange(52.0, 52.8));
      expect(n.position.longitude, inInclusiveRange(12.8, 14.0));
    }
    expect(
      () => generate(
        GeneratorSettings(type: 'tsp', countries: const {'VA'}, counts: g.counts, seed: 1),
        cities,
        name: 'S',
        problemName: 'P',
        networkName: 'N',
      ),
      throwsA(isA<GeneratorException>()),
    );
  });

  testWidgets('every problem type: nothing missing before solving', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    for (final type in modules.keys) {
      final s = generate(settings(type), cities, name: 'S', problemName: 'P', networkName: 'Netz');
      state.openScenario(s);
      expect(state.problem!.type, type);
      expect(state.nodeProblems, isEmpty, reason: type);
      final errors = state.spec!.validateParameters(state.problem!.parameters);
      // set and maximal covering: the radius is chosen afterwards (the smallest radius as a suggestion)
      expect(
        errors.where((e) => e.args['label'] != 'field.radius'),
        isEmpty,
        reason: '$type ${errors.map((e) => e.args)}',
      );
      if (state.spec!.network == NetworkUse.required) expect(state.network!.edges, isNotEmpty, reason: type);
    }
  });

  testWidgets('the dialog: the problem generated with the settings, shown at once and not saved yet', (tester) async {
    AppState.reverseGeocoding = false; // no postcodes from a core in this test
    SharedPreferences.setMockInitialValues({'language': 'de'});
    final state = (await tester.runAsync(AppState.create))!;
    await tester.runAsync(loadCities);
    Scenario? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showGeneratorDialog(context, state),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Zufallsproblem erzeugen'), findsOneWidget);
    expect(find.text('Deutschland'), findsOneWidget);
    expect(find.text('Anzahl Anbieter'), findsOneWidget);
    await tester.tap(find.text('Erzeugen'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.problems.single.type, 'tpp');
    expect(result!.nodes, hasLength(11));
    state.openGenerated(result!);
    expect(state.dirty, isTrue);
    expect(state.problem!.type, 'tpp');
  });

  test('addresses: city and country at once, the postcode of the place later', () async {
    final s = generate(
      settings('tpp'),
      cities,
      name: 'x',
      problemName: 'p',
      networkName: 'n',
      countryName: (c) => c == 'DE' ? 'Deutschland' : c,
    );
    for (final n in s.nodes) {
      final d = n.json['addressDetails'] as Map;
      expect(n.address, '${d['city']}, Deutschland');
      expect(d['country'], 'DE');
    }
    var asked = 0;
    await withPostcodes(s, (p) async => ++asked == 2 ? null : '1574$asked', countryName: (c) => 'Deutschland');
    expect(asked, s.nodes.length);
    final withCode = s.nodes.where((n) => (n.json['addressDetails'] as Map)['postcode'] != null).toList();
    expect(withCode, hasLength(s.nodes.length - 1));
    final d = withCode.first.json['addressDetails'] as Map;
    expect(withCode.first.address, '${d['postcode']} ${d['city']}, Deutschland');
  });

  test('postcodes offline: the addresses stay, the others are not asked', () async {
    final s = generate(settings('tsp'), cities, name: 'x', problemName: 'p', networkName: 'n');
    final before = [for (final n in s.nodes) n.address];
    var asked = 0;
    await withPostcodes(s, (p) async {
      asked++;
      throw Exception('offline');
    }, parallel: 3);
    expect(asked, 3);
    expect([for (final n in s.nodes) n.address], before);
  });
}
