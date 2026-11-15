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

  test('location problems: capacities of the candidates if a mean is given - they cover the demand', () {
    for (final type in ['wlp', 'pmedian', 'pcentre']) {
      final plan = GeneratorPlan.of(modules[type]!);
      final candidates = plan.groups.firstWhere((g) => g.key == 'sources');
      expect(candidates.fields.map((f) => f.key), contains('capacity'), reason: type);
      expect(plan.defaultMean(candidates.fields.firstWhere((f) => f.key == 'capacity')), isNull);
      // without a mean: no capacities
      final plain = generate(settings(type), cities, name: 'S', problemName: 'P', networkName: 'N');
      expect(plain.problems.single.parameters['isCapacitated'], isNot(true), reason: type);
      expect(plain.nodes.where((n) => n['capacity'] != null), isEmpty, reason: type);
      // with a mean: the problem respects them, together a quarter more than the demands
      final base = settings(type);
      final s = generate(
        GeneratorSettings(
          type: type,
          countries: base.countries,
          counts: base.counts,
          means: {...base.means, 'sources.capacity': 10, 'destinations.demand': 30},
          costPerKm: 1,
          seed: 1,
        ),
        cities,
        name: 'S',
        problemName: 'P',
        networkName: 'N',
      );
      expect(s.problems.single.parameters['isCapacitated'], isTrue, reason: type);
      num total(String role, String key) =>
          s.nodes.where((n) => n.roles.contains(role)).fold<num>(0, (t, n) => t + ((n[key] as num?) ?? 0));
      // p-median and p-centre: the p largest
      final caps = [for (final n in s.nodes.where((n) => n.roles.contains('candidate'))) n['capacity'] as num]
        ..sort((a, b) => b.compareTo(a));
      final p = s.problems.single.parameters['p'] as int? ?? caps.length;
      expect(caps.take(p).fold<num>(0, (a, b) => a + b), greaterThanOrEqualTo(1.25 * total('customer', 'demand')));
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

  test(
    'flows: a directed network, every node reached from every other - with capacities the customers along a flow',
    () {
      for (final type in ['mincostflow', 'maxflow', 'multicommodity', 'multimodal', 'multistagewlp']) {
        for (final seed in [1, 2, 3]) {
          final s = generate(
            settings(type, seed: seed),
            cities,
            name: 'S',
            problemName: 'P',
            networkName: 'N',
          );
          final net = s.networks.values.single;
          expect(net.directed, isTrue, reason: type);
          Set<String> from(String start, bool forward) {
            final reached = {start};
            var grown = true;
            while (grown) {
              grown = false;
              for (final e in net.edges) {
                final (a, b) = forward ? (e.from, e.to) : (e.to, e.from);
                if (reached.contains(a) && reached.add(b)) grown = true;
              }
            }
            return reached;
          }

          final all = {for (final n in s.nodes) n.id};
          if (net.edges.any((e) => e.json['capacity'] != null)) {
            // with capacities along a flow: every customer reached from the suppliers
            final reached = {
              for (final n in s.nodes)
                if (n.roles.contains('supplier')) ...from(n.id, true),
            };
            for (final n in s.nodes) {
              if (n.roles.contains('customer')) expect(reached, contains(n.id), reason: '$type $seed');
            }
          } else {
            expect(from(s.nodes.first.id, true), all, reason: '$type $seed');
            expect(from(s.nodes.first.id, false), all, reason: '$type $seed');
          }
          // no edge twice in the same direction
          final pairs = [for (final e in net.edges) '${e.from}>${e.to}'];
          expect(pairs.toSet(), hasLength(pairs.length), reason: '$type $seed');
        }
      }
      for (final type in ['shortestpath', 'cpp']) {
        final s = generate(settings(type), cities, name: 'S', problemName: 'P', networkName: 'N');
        expect(s.networks.values.single.directed, isFalse, reason: type);
      }
    },
  );

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

  test('addresses: city and country at once, position and postcode later from geocoding the address', () async {
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
    final table = [for (final n in s.nodes) n.position];
    var asked = 0;
    final addresses = <String>[];
    await withGeocodedPlaces(s, (address, near) async {
      addresses.add(address);
      return switch (++asked) {
        2 => null, // no hit
        3 => (position: LatLng(near.latitude + 2, near.longitude), postcode: '99999'), // a place far away
        _ => (position: LatLng(near.latitude + 0.01, near.longitude), postcode: '1574$asked'),
      };
    }, countryName: (c) => 'Deutschland');
    expect(asked, s.nodes.length);
    expect(addresses.every((a) => a.endsWith(', Deutschland')), isTrue);
    final moved = [
      for (final (k, n) in s.nodes.indexed)
        if (n.position != table[k]) n.id,
    ];
    expect(moved, hasLength(s.nodes.length - 2));
    final withCode = s.nodes.where((n) => (n.json['addressDetails'] as Map)['postcode'] != null).toList();
    expect([for (final n in withCode) n.id], moved);
    final d = withCode.first.json['addressDetails'] as Map;
    expect(withCode.first.address, '${d['postcode']} ${d['city']}, Deutschland');
  });

  test('geocoding offline: positions and addresses stay, the others are not asked', () async {
    final s = generate(settings('tsp'), cities, name: 'x', problemName: 'p', networkName: 'n');
    final before = [for (final n in s.nodes) (n.address, n.position)];
    var asked = 0;
    await withGeocodedPlaces(s, (address, near) async {
      asked++;
      throw Exception('offline');
    }, parallel: 3);
    expect(asked, 3);
    expect([for (final n in s.nodes) (n.address, n.position)], before);
  });
}
