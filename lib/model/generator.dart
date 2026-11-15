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

  /// a directed network - the flows (min cost flow and its relatives, max flow) from the suppliers or the source;
  /// shortest path and the Chinese postman undirected
  bool get directed => spec.group == ModuleGroup.network && spec.type != 'shortestpath';

  /// pickup and delivery: a delivery node for every pickup - one count for both
  bool get paired => spec.type == 'pdp';

  /// the total supply covers the total demand (transport, flows) - supply and demand of the nodes
  bool get canCover {
    final keys = {for (final g in groups) ...g.fields.map((f) => f.key)};
    return (keys.contains('supply') && keys.contains('demand')) ||
        (keys.contains('supplies') && keys.contains('demands')) ||
        (capacitated && keys.contains('capacity') && keys.contains('demand'));
  }

  /// a location problem with capacities of the candidates (isCapacitated) - they are used if a mean is given
  bool get capacitated => spec.parameters.any((f) => f.key == 'isCapacitated');

  factory GeneratorPlan.of(ModuleSpec spec) {
    final p = spec.defaultParameters();
    // the capacities of the candidates also without capacities by default - a mean switches them on
    final visible = {...p, if (spec.parameters.any((f) => f.key == 'isCapacitated')) 'isCapacitated': true};
    bool numeric(FieldSpec f) =>
        !f.computed &&
        f.defaultValue == null &&
        const {FieldKind.number, FieldKind.integer, FieldKind.unlimited, FieldKind.commodities}.contains(f.kind) &&
        f.isVisible(visible);
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
      // the address for the students - position and postcode come later from geocoding it (withGeocodedPlaces)
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
  // capacities of the candidates: the problem respects them
  final capacitated = plan.capacitated && g.means['sources.capacity'] != null;
  if (g.cover && plan.canCover) {
    _cover(
      byGroup,
      [for (final c in commodities) c['id'] as String],
      g.integer,
      capacities: capacitated,
      open: spec.parameters.any((f) => f.key == 'p') ? _locations(byGroup) : null,
    );
  }

  if (spec.usesVehicles) {
    // every quantity fits into a vehicle
    final largest = [
      for (final n in s.nodes) ...[n['demand'], n['amount']].whereType<num>(),
    ].fold<num>(0, math.max);
    s.json['vehicles'] = [
      {'id': 'V1', 'name': vehicleName, 'capacity': math.max(g.vehicleCapacity, largest)},
    ];
  }

  final problem = s.addProblem(g.type, problemName, {...plan.parameters, if (capacitated) 'isCapacitated': true});
  if (plan.withNetwork) {
    final directed = plan.directed;
    final net = s.addNetwork(networkName, directed: directed);
    final pairs = _edges(s.nodes);
    final values = [
      for (final _ in pairs)
        <String, dynamic>{
          for (final f in plan.edgeFields)
            if (g.means['edge.${f.key}'] case final num mean) f.key: vary(mean),
        },
    ];
    // (connection, from, to)
    var arcs = [for (final (k, (a, b)) in pairs.indexed) (k, a, b)];
    if (directed) {
      // from a supplier - max flow: from its source, the first of the two farthest nodes
      final all = byGroup[GeneratorGroup.nodes] ?? const <Node>[];
      final starts = byGroup['sources'] ?? [if (_farthest(all) case (final a, _)) a];
      arcs = _directed(s.nodes, pairs, starts);
      // capacities: the connections a feasible flow uses in its direction
      if (spec.type != 'maxflow') arcs = _alongFlow(s.nodes, pairs, values, arcs);
    }
    for (final (k, a, b) in arcs) {
      net.addEdge(a.id, b.id).json.addAll(values[k]);
    }
    // multimodal: the train on the longer half of the edges
    if (spec.usesModes) {
      double length(int k) => _km(pairs[k].$1.position, pairs[k].$2.position);
      final lengths = [for (final (k, _, _) in arcs) length(k)]..sort();
      final median = lengths[lengths.length ~/ 2];
      for (final (i, e) in net.edges.indexed) {
        if (length(arcs[i].$1) < median) e.json['modes'] = <String, dynamic>{'M1': <String, dynamic>{}};
      }
    }
    problem.network = networkName;
  }
  _parameters(problem, spec, s, byGroup, g);
  return s;
}

/// supplies so large that they cover the demands - each by the same factor, per commodity. capacities: those of the
/// candidates of a location problem a quarter more than the demands - every customer from one location (single
/// source) stays possible; open: p-median and p-centre the p largest of them (as the check before solving)
void _cover(
  Map<String, List<Node>> byGroup,
  List<String> commodities,
  bool integer, {
  bool capacities = false,
  int? open,
}) {
  final sources = byGroup['sources'] ?? const <Node>[], destinations = byGroup['destinations'] ?? const <Node>[];
  num sum(List<Node> nodes, String key, String? c) => nodes.fold<num>(0, (t, n) {
    final v = c == null ? n[key] : (n[key] as Map?)?[c];
    return t + (v is num ? v : 0);
  });
  // the capacity of the open locations: the largest ones
  num largest(String key) {
    final values = [for (final n in sources) (n[key] as num?) ?? 0]..sort((a, b) => b.compareTo(a));
    return values.take(open ?? values.length).fold<num>(0, (t, v) => t + v);
  }

  void scale(String key, String? c, double factor) {
    for (final n in sources) {
      if (c == null) {
        if (n[key] case final num v) n[key] = integer ? (v * factor).ceil() : v * factor;
      } else if ((n[key] as Map?)?[c] case final num v) {
        (n[key] as Map)[c] = integer ? (v * factor).ceil() : v * factor;
      }
    }
  }

  for (final (supply, demand, c, margin) in [
    if (capacities)
      ('capacity', 'demand', null, 1.25)
    else if (commodities.isEmpty)
      ('supply', 'demand', null, 1.0)
    else
      for (final c in commodities) ('supplies', 'demands', c, 1.0),
  ]) {
    final have = capacities ? largest(supply) : sum(sources, supply, c), need = sum(destinations, demand, c) * margin;
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

/// the edges directed so that every node can be reached from every other (strongly connected, Robbins): a depth-first
/// search from the first start node (supplier, source) - its tree edges away from it, the other edges back to the
/// node reached earlier; an edge without which the network falls apart (bridge) in both directions. So every
/// supplier reaches every customer - with unlimited capacities a problem stays solvable that is solvable undirected
List<(int, Node, Node)> _directed(List<Node> nodes, List<(Node, Node)> edges, List<Node> starts) {
  final index = {for (final (k, n) in nodes.indexed) n.id: k};
  final near = <int, List<(int, int)>>{}; // node -> (neighbour, edge)
  for (final (e, (a, b)) in edges.indexed) {
    final i = index[a.id]!, j = index[b.id]!;
    (near[i] ??= []).add((j, e));
    (near[j] ??= []).add((i, e));
  }
  // nearest neighbours first
  for (final MapEntry(key: i, value: list) in near.entries) {
    list.sort(
      (x, y) => _km(nodes[i].position, nodes[x.$1].position).compareTo(_km(nodes[i].position, nodes[y.$1].position)),
    );
  }
  final disc = List<int>.filled(nodes.length, -1), low = List<int>.filled(nodes.length, 0);
  final result = <(int, Node, Node)>[];
  final seen = <int>{}; // edges directed
  var time = 0;
  final root = starts.isEmpty ? 0 : index[starts.first.id]!;
  // iterative depth-first search: (node, edge to it, next neighbour)
  final stack = <(int, int, int)>[(root, -1, 0)];
  disc[root] = low[root] = time++;
  while (stack.isNotEmpty) {
    final (v, via, k) = stack.removeLast();
    final list = near[v] ?? const <(int, int)>[];
    if (k < list.length) {
      stack.add((v, via, k + 1));
      final (w, e) = list[k];
      if (e == via || seen.contains(e)) continue;
      seen.add(e);
      if (disc[w] < 0) {
        result.add((e, nodes[v], nodes[w])); // tree edge
        disc[w] = low[w] = time++;
        stack.add((w, e, 0));
      } else {
        result.add((e, nodes[v], nodes[w])); // back to a node reached earlier
        if (disc[w] < low[v]) low[v] = disc[w];
      }
    } else if (stack.isNotEmpty) {
      final parent = stack.last.$1;
      if (low[v] < low[parent]) low[parent] = low[v];
      if (low[v] > disc[parent]) result.add((via, nodes[v], nodes[parent])); // bridge - also back
    }
  }
  result.sort((x, y) => x.$1.compareTo(y.$1));
  return result;
}

/// the connections with capacities (edges, warehouses) directed along a flow that delivers the demands - the
/// largest flow from the suppliers to the customers in the undirected network (Edmonds-Karp); a connection it uses
/// in its direction only, the others as [arcs]. Without capacities or if the demands cannot be delivered even
/// undirected: [arcs] unchanged
List<(int, Node, Node)> _alongFlow(
  List<Node> nodes,
  List<(Node, Node)> pairs,
  List<Map<String, dynamic>> values,
  List<(int, Node, Node)> arcs,
) {
  num? limit(Object? v) => v is num ? v : null;
  num amount(Object? v) => v is num ? v : (v is Map ? v.values.whereType<num>().fold<num>(0, (a, b) => a + b) : 0);
  final nodeCap = [for (final n in nodes) n.roles.contains('candidate') ? limit(n['capacity']) : null];
  if (values.every((v) => limit(v['capacity']) == null) && nodeCap.every((c) => c == null)) return arcs;

  // network of the flow: node v in = v, out = n + v (edge in -> out: its capacity), source 2n, sink 2n + 1
  final n = nodes.length, source = 2 * n, sink = 2 * n + 1;
  final index = {for (final (k, v) in nodes.indexed) v.id: k};
  final to = <int>[], cap = <double>[], head = List<List<int>>.generate(2 * n + 2, (_) => []);
  int add(int a, int b, double c) {
    head[a].add(to.length);
    to.add(b);
    cap.add(c);
    head[b].add(to.length);
    to.add(a);
    cap.add(0);
    return to.length - 2;
  }

  const unlimited = 1e12;
  var demand = 0.0;
  for (var v = 0; v < n; v++) {
    add(v, n + v, (nodeCap[v] ?? unlimited).toDouble());
    final sup = amount(nodes[v]['supply'] ?? nodes[v]['supplies']).toDouble();
    final dem = amount(nodes[v]['demand'] ?? nodes[v]['demands']).toDouble();
    if (sup > 0) add(source, v, sup);
    if (dem > 0) add(n + v, sink, dem);
    demand += dem;
  }
  if (demand <= 0) return arcs;
  // a connection both ways: a -> b and b -> a, each with its capacity
  final forward = <int>[], backward = <int>[];
  for (final (k, (a, b)) in pairs.indexed) {
    final c = (limit(values[k]['capacity']) ?? unlimited).toDouble();
    final i = index[a.id]!, j = index[b.id]!;
    forward.add(add(n + i, j, c));
    backward.add(add(n + j, i, c));
  }
  var flow = 0.0;
  while (true) {
    final prev = List<int>.filled(2 * n + 2, -1);
    final queue = [source];
    prev[source] = -2;
    for (var q = 0; q < queue.length && prev[sink] == -1; q++) {
      for (final e in head[queue[q]]) {
        if (cap[e] > 1e-9 && prev[to[e]] == -1) {
          prev[to[e]] = e;
          queue.add(to[e]);
        }
      }
    }
    if (prev[sink] == -1) break;
    var push = double.infinity;
    for (var v = sink; v != source; v = to[prev[v] ^ 1]) {
      push = math.min(push, cap[prev[v]]);
    }
    for (var v = sink; v != source; v = to[prev[v] ^ 1]) {
      cap[prev[v]] -= push;
      cap[prev[v] ^ 1] += push;
    }
    flow += push;
  }
  if (flow < demand - 1e-6) return arcs;
  // net flow of a connection: what a -> b carries minus what b -> a carries
  final direction = [for (var k = 0; k < pairs.length; k++) cap[forward[k] ^ 1] - cap[backward[k] ^ 1]];
  final both = {
    for (final (k, _, _) in arcs)
      if (arcs.where((x) => x.$1 == k).length > 1) k,
  };
  return [
    for (final arc in arcs)
      if (both.contains(arc.$1) || direction[arc.$1].abs() < 1e-9)
        arc
      else if (direction[arc.$1] > 0)
        (arc.$1, pairs[arc.$1].$1, pairs[arc.$1].$2)
      else
        (arc.$1, pairs[arc.$1].$2, pairs[arc.$1].$1),
  ];
}

/// the two nodes farthest apart - null with less than two
(Node, Node)? _farthest(List<Node> all) {
  if (all.length < 2) return null;
  var best = (all[0], all[1]);
  for (final a in all) {
    for (final b in all) {
      if (_km(a.position, b.position) > _km(best.$1.position, best.$2.position)) best = (a, b);
    }
  }
  return best;
}

/// the number of locations of a p-median, p-centre or maximal covering: a third of the candidates
int _locations(Map<String, List<Node>> byGroup) {
  final candidates = (byGroup['sources'] ?? const <Node>[]).where((n) => n.roles.contains('candidate')).length;
  return math.max(1, (candidates / 3).ceil());
}

/// the parameters a problem needs: start and end, source and sink (the farthest nodes), the number of locations and
/// the budget of a maximal covering
void _parameters(Problem problem, ModuleSpec spec, Scenario s, Map<String, List<Node>> byGroup, GeneratorSettings g) {
  final p = problem.parameters;
  final all = byGroup[GeneratorGroup.nodes] ?? const <Node>[];
  (Node, Node)? farthest() => _farthest(all);

  final locations = _locations(byGroup);
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

/// a place found by geocoding the address of a node: its position and the postcode - null: none
typedef GeocodedPlace = ({LatLng position, String? postcode});

/// the farthest a hit may lie from the city of the table - a place of the same name elsewhere is not taken
const maxPlaceShiftKm = 50.0;

/// the positions of the places of a generated scenario from their addresses (geocoding) and the postcodes -
/// [placeOf] gives the place of an address, hits near the city of the table first; null, a hit farther than
/// [maxPlaceShiftKm] or an error leave the node at the position of the table and the address without a postcode;
/// a few requests at a time - none of them answered (offline): the others are not asked
Future<void> withGeocodedPlaces(
  Scenario s,
  Future<GeocodedPlace?> Function(String address, LatLng near) placeOf, {
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
            final address = n.address;
            if (address == null || n.json['addressDetails'] is! Map) return;
            final place = await placeOf(address, n.position);
            if (place == null || _km(place.position, n.position) > maxPlaceShiftKm) return;
            n.position = place.position;
            final postcode = place.postcode?.trim() ?? '';
            final withCode = addressWithPostcode(n, postcode, countryName);
            if (withCode == null) return;
            n.address = withCode;
            (n.json['addressDetails'] as Map)['postcode'] = postcode;
          } catch (_) {
            failed++;
          }
        }(),
    ]);
    if (failed == batch) return;
  }
}
