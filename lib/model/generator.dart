/// Random problems for exercises: cities of Europe as nodes, the values of the nodes around the means entered -
/// varied at random by a percentage. The same settings and start value (seed) give the same problem.
///
/// The cities come from the Basic World Cities Database (simplemaps.com, CC BY 4.0) - assets/data/cities.tsv.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../modules/modules.dart';
import 'scenario.dart';

class City {
  final String name;
  final LatLng position;
  final String country; // ISO 3166 alpha-2, e.g. DE
  const City(this.name, this.position, this.country);
}

/// the cities of the file: name, lat, lon and country separated by tabs - lines with # are comments
List<City> parseCities(String text) => [
  for (final line in text.split('\n'))
    if (line.isNotEmpty && !line.startsWith('#'))
      if (line.split('\t') case [final name, final lat, final lon, final country])
        City(name, LatLng(double.parse(lat), double.parse(lon)), country.trim()),
];

/// nodes of the problem the generator creates - those of a role (key of the RoleSpec), all nodes of a problem
/// without roles (tsp, cpp, shortest path, max flow between two nodes) or the transshipment nodes of a network flow
class GeneratorGroup {
  static const nodes = 'nodes';
  static const transit = 'transit';

  final String key;
  final String? nodeRole; // role of its nodes - null: none
  final List<FieldSpec> fields; // the values with a mean - numbers of the nodes or a number per commodity
  const GeneratorGroup(this.key, this.nodeRole, this.fields);

  String get label => nodeRole == null ? 'ui.generator.nodes' : 'role.$nodeRole.plural';
}

/// what the generator of a problem type asks for: the groups of nodes, the values of the edges, vehicles and
/// commodities
class GeneratorPlan {
  final ModuleSpec spec;
  final Map<String, dynamic> parameters; // those of the new problem
  final List<GeneratorGroup> groups;
  final List<FieldSpec> edgeFields;
  const GeneratorPlan._(this.spec, this.parameters, this.groups, this.edgeFields);

  bool get withNetwork => spec.network == NetworkUse.required;
  bool get withCosts => spec.usesMatrix && spec.group != ModuleGroup.routing;

  /// pickup and delivery: a delivery node for every pickup - one count for both
  bool get paired => spec.type == 'pdp';

  /// the total supply covers the total demand (transport, flows) - supply and demand of the nodes
  bool get canCover {
    final keys = {for (final g in groups) ...g.fields.map((f) => f.key)};
    return (keys.contains('supply') && keys.contains('demand')) ||
        (keys.contains('supplies') && keys.contains('demands'));
  }

  factory GeneratorPlan.of(ModuleSpec spec) {
    final p = spec.defaultParameters();
    bool numeric(FieldSpec f) =>
        !f.computed &&
        f.defaultValue == null &&
        const {FieldKind.number, FieldKind.integer, FieldKind.unlimited, FieldKind.commodities}.contains(f.kind) &&
        f.isVisible(p);
    final roles = spec.activeRoles(p);
    final groups = [
      for (final r in roles) GeneratorGroup(r.key, spec.nodeRole(r, p), [...r.nodeFields.where(numeric)]),
      if (roles.isEmpty) const GeneratorGroup(GeneratorGroup.nodes, null, []),
      // the transshipment nodes between the suppliers and customers of a flow
      if (roles.isNotEmpty && spec.network == NetworkUse.required)
        const GeneratorGroup(GeneratorGroup.transit, 'transit', []),
    ];
    final edges = [
      for (final f in spec.edgeFields)
        if (f.kind != FieldKind.modes && numeric(f)) f,
    ];
    return GeneratorPlan._(spec, p, groups, edges);
  }

  /// count of nodes of a group in a new dialog
  int defaultCount(GeneratorGroup g) => switch (g.key) {
    'depots' => 1,
    'sources' when g.nodeRole == 'candidate' => 6,
    'sources' when g.nodeRole == 'pickup' => 4,
    'sources' => 3,
    'warehouses' => 4,
    GeneratorGroup.transit => 4,
    GeneratorGroup.nodes => spec.type == 'shortestpath' ? 12 : 10,
    _ => 8,
  };

  /// mean of a value in a new dialog - the main values have one, the others are empty (not set)
  num? defaultMean(FieldSpec f) => switch (f.key) {
    'supply' || 'supplies' => spec.type == 'maxflow' ? null : 100,
    'demand' || 'demands' => spec.type == 'maxflow' ? null : (spec.usesVehicles ? 20 : 30),
    'amount' => 10,
    'fixedCost' => 10000,
    'capacity' => spec.type == 'maxflow' ? 100 : (spec.type == 'multistagewlp' ? 150 : null),
    _ => null,
  };
}

class GeneratorSettings {
  final String type;
  final Set<String> countries; // ISO codes - empty: all
  final (LatLng, LatLng)? section; // south-west and north-east corner - only cities in it
  final Map<String, int> counts; // per group
  final Map<String, num?> means; // '<group>.<field>' and 'edge.<field>' - null: not set
  final double variation; // e.g. 0.3: ± 30 % around the mean
  final bool integer; // whole numbers
  final bool cover; // the total supply covers the total demand
  final int commodities; // multi-commodity flow
  final num vehicleCapacity; // vrp, pdp
  final num? costPerKm;
  final int seed;

  const GeneratorSettings({
    required this.type,
    this.countries = const {},
    this.section,
    required this.counts,
    this.means = const {},
    this.variation = 0.3,
    this.integer = true,
    this.cover = true,
    this.commodities = 2,
    this.vehicleCapacity = 100,
    this.costPerKm,
    required this.seed,
  });
}

class GeneratorException implements Exception {
  final String key; // message key
  final Map<String, Object> args;
  const GeneratorException(this.key, [this.args = const {}]);
}

/// the cities of the region - the countries and the section of the map
List<City> citiesIn(List<City> cities, Set<String> countries, (LatLng, LatLng)? section) => [
  for (final c in cities)
    if (countries.isEmpty || countries.contains(c.country))
      if (section == null ||
          (c.position.latitude >= section.$1.latitude &&
              c.position.latitude <= section.$2.latitude &&
              c.position.longitude >= section.$1.longitude &&
              c.position.longitude <= section.$2.longitude))
        c,
];

const _distance = Distance();
double _km(LatLng a, LatLng b) => _distance.as(LengthUnit.Kilometer, a, b);

/// n cities of the region spread over it: at least a distance apart that shrinks until there are enough
List<City> _pick(List<City> region, int n, math.Random random) {
  if (n > region.length) throw GeneratorException('ui.generator.tooFew', {'n': n, 'cities': region.length});
  final lat = [for (final c in region) c.position.latitude], lon = [for (final c in region) c.position.longitude];
  final sw = LatLng(lat.reduce(math.min), lon.reduce(math.min)),
      ne = LatLng(lat.reduce(math.max), lon.reduce(math.max));
  final area = _km(sw, LatLng(sw.latitude, ne.longitude)) * _km(sw, LatLng(ne.latitude, sw.longitude));
  var gap = 0.7 * math.sqrt(area / (n * math.pi));
  final order = [...region]..shuffle(random);
  while (true) {
    final chosen = <City>[];
    for (final c in order) {
      if (chosen.every((o) => _km(o.position, c.position) >= gap)) chosen.add(c);
      if (chosen.length == n) return chosen;
    }
    gap = gap < 1 ? 0 : gap * 0.7;
  }
}

/// a new scenario with one problem of the type - its nodes in random cities of the region. The names in the language
/// of the app: of the scenario, problem, network, vehicle and the two modes (road, rail)
Scenario generate(
  GeneratorSettings g,
  List<City> cities, {
  required String name,
  required String problemName,
  required String networkName,
  String vehicleName = 'V1',
  (String, String) modeNames = ('M1', 'M2'),
  String Function(String code)? countryName,
}) {
  final spec = modules[g.type]!;
  final plan = GeneratorPlan.of(spec);
  final random = math.Random(g.seed);
  final s = Scenario.empty();
  s.json['id'] = 'random-${g.type}-${g.seed}';
  s.json['name'] = name;
  if (plan.withCosts && g.costPerKm != null) s.matrix['costPerKm'] = g.costPerKm;

  int count(GeneratorGroup group) {
    final key = plan.paired && group.key == 'destinations' ? 'sources' : group.key;
    return g.counts[key] ?? plan.defaultCount(group);
  }

  final total = plan.groups.fold(0, (n, group) => n + count(group));
  if (total < 2) throw const GeneratorException('ui.check.twoNodes');
  final picked = _pick(citiesIn(cities, g.countries, g.section), total, random);
  // the names unique - the same name in two countries with the country
  final names = <String, int>{};
  for (final c in picked) {
    names.update(c.name, (n) => n + 1, ifAbsent: () => 1);
  }

  // commodities and modes of the scenario
  final commodities = [
    if (spec.usesCommodities)
      for (var k = 1; k <= math.max(1, g.commodities); k++) {'id': 'G$k', 'name': 'G$k', 'capacityFactor': 1.0},
  ];
  if (commodities.isNotEmpty) s.json['commodities'] = commodities;
  if (spec.usesModes) {
    s.json['modes'] = [
      {'id': 'M1', 'name': modeNames.$1, 'costPerKm': 1.0},
      {'id': 'M2', 'name': modeNames.$2, 'costPerKm': 0.5, 'fixedCost': 500.0},
    ];
  }

  num vary(num mean) {
    final v = mean * (1 + g.variation * (2 * random.nextDouble() - 1));
    return math.max(0, g.integer ? v.round() : (v * 100).round() / 100);
  }

  final byGroup = <String, List<Node>>{};
  var next = 0;
  for (final group in plan.groups) {
    for (var i = 0; i < count(group); i++) {
      final c = picked[next++];
      final n = s.addNode(c.position, roles: group.nodeRole == null ? const [] : [group.nodeRole!]);
      n.name = names[c.name]! > 1 ? '${c.name} (${c.country})' : c.name;
      // the address for the students - the postcode comes later (withPostcodes)
      n.address = '${c.name}, ${countryName?.call(c.country) ?? c.country}';
      n.json['addressDetails'] = {'city': c.name, 'country': c.country};
      for (final f in group.fields) {
        final mean = g.means['${group.key}.${f.key}'];
        if (mean == null) continue;
        n[f.key] = f.kind == FieldKind.commodities
            ? {for (final c in commodities) c['id'] as String: vary(mean)}
            : (f.kind == FieldKind.integer ? vary(mean).round() : vary(mean));
      }
      (byGroup[group.key] ??= []).add(n);
    }
  }
  if (plan.paired) {
    final pickups = byGroup['sources'] ?? const [], deliveries = byGroup['destinations'] ?? const [];
    for (var i = 0; i < pickups.length; i++) {
      pickups[i]['deliveryTo'] = deliveries[i].id;
    }
  }
  if (g.cover && plan.canCover) _cover(byGroup, [for (final c in commodities) c['id'] as String], g.integer);

  if (spec.usesVehicles) {
    // every quantity fits into a vehicle
    final largest = [
      for (final n in s.nodes) ...[n['demand'], n['amount']].whereType<num>(),
    ].fold<num>(0, math.max);
    s.json['vehicles'] = [
      {'id': 'V1', 'name': vehicleName, 'capacity': math.max(g.vehicleCapacity, largest)},
    ];
  }

  final problem = s.addProblem(g.type, problemName, plan.parameters);
  if (plan.withNetwork) {
    final net = s.addNetwork(networkName, directed: false);
    final edges = _edges(s.nodes);
    for (final (a, b) in edges) {
      final e = net.addEdge(a.id, b.id);
      for (final f in plan.edgeFields) {
        if (g.means['edge.${f.key}'] case final num mean) e.json[f.key] = vary(mean);
      }
    }
    // multimodal: the train on the longer half of the edges
    if (spec.usesModes) {
      final lengths = [for (final (a, b) in edges) _km(a.position, b.position)]..sort();
      final median = lengths[lengths.length ~/ 2];
      for (final (k, e) in net.edges.indexed) {
        if (_km(edges[k].$1.position, edges[k].$2.position) < median) {
          e.json['modes'] = <String, dynamic>{'M1': <String, dynamic>{}};
        }
      }
    }
    problem.network = networkName;
  }
  _parameters(problem, spec, s, byGroup, g);
  return s;
}

/// supplies so large that they cover the demands - each by the same factor, per commodity
void _cover(Map<String, List<Node>> byGroup, List<String> commodities, bool integer) {
  final sources = byGroup['sources'] ?? const <Node>[], destinations = byGroup['destinations'] ?? const <Node>[];
  num sum(List<Node> nodes, String key, String? c) => nodes.fold<num>(0, (t, n) {
    final v = c == null ? n[key] : (n[key] as Map?)?[c];
    return t + (v is num ? v : 0);
  });
  void scale(String key, String? c, double factor) {
    for (final n in sources) {
      if (c == null) {
        if (n[key] case final num v) n[key] = integer ? (v * factor).ceil() : v * factor;
      } else if ((n[key] as Map?)?[c] case final num v) {
        (n[key] as Map)[c] = integer ? (v * factor).ceil() : v * factor;
      }
    }
  }

  for (final (supply, demand, c) in [
    if (commodities.isEmpty) ('supply', 'demand', null) else for (final c in commodities) ('supplies', 'demands', c),
  ]) {
    final have = sum(sources, supply, c), need = sum(destinations, demand, c);
    if (have > 0 && have < need) scale(supply, c, need / have);
  }
}

/// a connected network: the shortest connections that join all nodes (minimum spanning tree) and from every node
/// to its two nearest neighbours - each pair once
List<(Node, Node)> _edges(List<Node> nodes) {
  final n = nodes.length;
  final d = [
    for (final a in nodes) [for (final b in nodes) _km(a.position, b.position)],
  ];
  final pairs = <(int, int)>{};
  void add(int i, int j) => pairs.add(i < j ? (i, j) : (j, i));
  // Prim
  final inTree = {0};
  while (inTree.length < n) {
    (int, int)? best;
    for (final i in inTree) {
      for (var j = 0; j < n; j++) {
        if (!inTree.contains(j) && (best == null || d[i][j] < d[best.$1][best.$2])) best = (i, j);
      }
    }
    add(best!.$1, best.$2);
    inTree.add(best.$2);
  }
  for (var i = 0; i < n; i++) {
    final near = [
      for (var j = 0; j < n; j++)
        if (j != i) j,
    ]..sort((a, b) => d[i][a].compareTo(d[i][b]));
    for (final j in near.take(2)) {
      add(i, j);
    }
  }
  return [for (final (i, j) in pairs) (nodes[i], nodes[j])];
}

/// the parameters a problem needs: start and end, source and sink (the farthest nodes), the number of locations and
/// the budget of a maximal covering
void _parameters(Problem problem, ModuleSpec spec, Scenario s, Map<String, List<Node>> byGroup, GeneratorSettings g) {
  final p = problem.parameters;
  final all = byGroup[GeneratorGroup.nodes] ?? const <Node>[];
  (Node, Node)? farthest() {
    if (all.length < 2) return null;
    var best = (all[0], all[1]);
    for (final a in all) {
      for (final b in all) {
        if (_km(a.position, b.position) > _km(best.$1.position, best.$2.position)) best = (a, b);
      }
    }
    return best;
  }

  final candidates = (byGroup['sources'] ?? const <Node>[]).where((n) => n.roles.contains('candidate')).length;
  final locations = math.max(1, (candidates / 3).ceil());
  for (final f in spec.parameters) {
    if (!f.required || !f.isVisible(p) || p[f.key] != null) continue;
    switch (f.key) {
      case 'startNode' || 'source':
        if (farthest() case (final a, _)) p[f.key] = a.id;
      case 'endNode' || 'sink':
        if (farthest() case (_, final b)) p[f.key] = b.id;
      case 'p':
        p['p'] = locations;
      case 'maxSrcCost':
        final mean = g.means['sources.fixedCost'];
        p['maxSrcCost'] = f.kind == FieldKind.integer || mean == null ? locations : mean * locations;
    }
  }
}

/// the address of a node with the postcode of its place - "15745 Wildau, Deutschland"; null if the node has no
/// address of the generator (city and country) or the postcode is empty
String? addressWithPostcode(Node n, String postcode, String Function(String code)? countryName) {
  final d = n.json['addressDetails'];
  if (d is! Map || d['city'] is! String || d['country'] is! String || postcode.trim().isEmpty) return null;
  final country = d['country'] as String;
  return '${postcode.trim()} ${d['city']}, ${countryName?.call(country) ?? country}';
}

/// the postcodes of the places of a generated scenario - [postcodeOf] gives the postcode at a position (reverse
/// geocoding), null or an error leave the address without it; a few requests at a time - none of them answered
/// (offline): the others are not asked
Future<void> withPostcodes(
  Scenario s,
  Future<String?> Function(LatLng position) postcodeOf, {
  String Function(String code)? countryName,
  int parallel = 6,
}) async {
  final nodes = [...s.nodes];
  for (var i = 0; i < nodes.length; i += parallel) {
    var failed = 0;
    final batch = nodes.skip(i).take(parallel).length;
    await Future.wait([
      for (final n in nodes.skip(i).take(parallel))
        () async {
          try {
            final postcode = await postcodeOf(n.position);
            final address = postcode == null ? null : addressWithPostcode(n, postcode, countryName);
            if (address == null) return;
            n.address = address;
            (n.json['addressDetails'] as Map)['postcode'] = postcode!.trim();
          } catch (_) {
            failed++;
          }
        }(),
    ]);
    if (failed == batch) return;
  }
}
