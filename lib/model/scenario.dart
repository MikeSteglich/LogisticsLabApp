/// Scenario file (.llab) of LogisticsLab - see pyLogisticsLab/docs/dateiformate.md.
///
/// The app works on the JSON of the file: fields it does not know (yet) are kept and written back unchanged.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';

const nodeRoles = ['supplier', 'customer', 'candidate', 'depot', 'transit', 'pickup', 'delivery'];

// the values of a data variant (as in the core): quantities, capacities and costs - not the identity, place and
// roles of a node or the ends of an edge
const variantNodeFields = {
  'supply', 'minSupply', 'maxSupply', 'demand', 'minDemand', 'maxDemand', 'capacity', 'fixedCost', 'costFactor', //
  'price', 'unitCost', 'timeWindow', 'serviceTime', 'serviceTimePerUnit', 'amount', 'minCap', 'maxCap',
  'shortageCost', 'supplies', 'demands', 'capacityFactors',
};
const variantEdgeFields = {'capacity', 'minFlow', 'fixedCost', 'modes', 'commodities'};

/// the values of a node or an edge in a data variant: the value of the variant if it has one, else the base value -
/// a change of the variant is stored in json.variants of the variant only where it differs from the base
class _Values {
  final Map<String, dynamic> json;
  final String? variant;
  final Set<String> fields;
  const _Values(this.json, this.variant, this.fields);

  bool _inVariant(String key) => variant != null && fields.contains(key);
  Map<String, dynamic>? get _own => ((json['variants'] as Map?)?[variant] as Map?)?.cast<String, dynamic>();

  Object? get(String key) {
    if (_inVariant(key) && (_own?.containsKey(key) ?? false)) return _own![key];
    return json[key];
  }

  void set(String key, Object? v) {
    if (!_inVariant(key)) {
      v == null ? json.remove(key) : json[key] = v;
      return;
    }
    final all = (json['variants'] ??= <String, dynamic>{}) as Map;
    final own = (all[variant] ??= <String, dynamic>{}) as Map;
    // the same as the base: no own value
    if (const DeepCollectionEquality().equals(v, json[key])) {
      own.remove(key);
    } else {
      own[key] = v;
    }
    if (own.isEmpty) all.remove(variant);
    if (all.isEmpty) json.remove('variants');
  }

  /// the value differs from the base in the variant
  bool differs(String key) => _inVariant(key) && (_own?.containsKey(key) ?? false);

  /// back to the base value
  void reset(String key) {
    if (!differs(key)) return;
    set(key, json[key]);
  }
}

class Node {
  final Map<String, dynamic> json;
  final String? variant; // data variant of the values - null: the base values
  Node(this.json, {this.variant});
  _Values get _values => _Values(json, variant, variantNodeFields);

  String get id => json['id'] as String;
  set id(String v) => json['id'] = v;
  String get name => (json['name'] as String?) ?? id;
  set name(String v) => json['name'] = v;
  String? get address => json['address'] as String?;
  set address(String? v) => v == null || v.isEmpty ? json.remove('address') : json['address'] = v;

  LatLng get position {
    final c = json['coordinates'] as List;
    return LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble());
  }

  set position(LatLng p) => json['coordinates'] = [_round(p.latitude), _round(p.longitude)];

  List<String> get roles => [...((json['roles'] as List?) ?? const []).cast<String>()];
  set roles(List<String> v) => json['roles'] = [
    for (final r in nodeRoles)
      if (v.contains(r)) r,
  ];
  bool get active => json['active'] as bool? ?? true;
  set active(bool v) => v ? json.remove('active') : json['active'] = false;

  /// attribute of a problem type, e.g. supply - in the data variant; null removes it (in a variant: empty)
  Object? operator [](String key) => _values.get(key);
  void operator []=(String key, Object? v) => _values.set(key, v);

  /// the value differs from the base in the data variant - reset: the base value again
  bool differs(String key) => _values.differs(key);
  void reset(String key) => _values.reset(key);

  static double _round(double v) => (v * 1e6).roundToDouble() / 1e6;
}

class Edge {
  final Map<String, dynamic> json;
  final String? variant; // data variant of the values - null: the base values
  Edge(this.json, {this.variant});
  _Values get _values => _Values(json, variant, variantEdgeFields);
  String get from => json['from'] as String;
  set from(String v) => json['from'] = v;
  String get to => json['to'] as String;
  set to(String v) => json['to'] = v;

  /// direction of the edge - its own (directed) or that of its network
  bool directedIn(Network net) => json['directed'] as bool? ?? net.directed;

  /// arrow of the edge: one way or both ways
  String arrowIn(Network net) => directedIn(net) ? '→' : '↔';

  /// attribute of a problem type, e.g. capacity - in the data variant; null removes it (in a variant: empty)
  Object? operator [](String key) => _values.get(key);
  void operator []=(String key, Object? v) => _values.set(key, v);

  bool differs(String key) => _values.differs(key);
  void reset(String key) => _values.reset(key);
}

class Network {
  final String name;
  final Map<String, dynamic> json;
  final String? variant; // data variant of the values of the edges
  Network(this.name, this.json, {this.variant});

  bool get directed => json['directed'] as bool? ?? false;
  set directed(bool v) => json['directed'] = v;
  List<Edge> get edges => [
    for (final e in (json['edges'] as List? ?? const [])) Edge(e as Map<String, dynamic>, variant: variant),
  ];
  List<dynamic> get _edges => (json['edges'] ??= <dynamic>[]) as List<dynamic>;

  /// the connection from - to exists already (both directions for an undirected edge)
  bool hasEdge(String from, String to) =>
      edges.any((e) => (e.from == from && e.to == to) || (!e.directedIn(this) && e.from == to && e.to == from));

  Edge addEdge(String from, String to) {
    final e = Edge({'from': from, 'to': to}, variant: variant);
    _edges.add(e.json);
    return e;
  }

  void removeEdgeAt(int i) => _edges.removeAt(i);
}

class Problem {
  final Map<String, dynamic> json;
  Problem(this.json);

  String get name => json['name'] as String;
  set name(String v) => json['name'] = v;
  String get type => json['type'] as String;
  Map<String, dynamic> get parameters => (json['parameters'] ??= <String, dynamic>{}) as Map<String, dynamic>;
  String? get network => json['network'] as String?;
  set network(String? v) => v == null ? json.remove('network') : json['network'] = v;
  // data variant of the values of the nodes and edges - null: the base values
  String? get variant => json['variant'] as String?;
  set variant(String? v) => v == null ? json.remove('variant') : json['variant'] = v;
}

class Scenario {
  final Map<String, dynamic> json;
  Scenario(this.json);

  factory Scenario.parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> || j['format'] != 'logisticsLab') {
      throw const FormatException('no LogisticsLab scenario (format logisticsLab)');
    }
    return Scenario(j);
  }

  // the maps typed as those of a parsed file - a map of strings would refuse a number (costPerKm)
  factory Scenario.empty() => Scenario(<String, dynamic>{
    'format': 'logisticsLab',
    'version': 1,
    'id': 'scenario',
    'name': '',
    'units': <String, dynamic>{'distance': 'km', 'time': 'min'},
    'matrix': <String, dynamic>{'matrixSource': 'osm', 'travelmode': 'car'},
    'nodes': <dynamic>[],
    'problems': <dynamic>[],
  });

  String toText() => '${const JsonEncoder.withIndent('  ').convert(json)}\n';

  String get id => json['id'] as String? ?? 'scenario';
  String? get name => json['name'] as String?;

  // data variant of the values of nodes and edges - that of the chosen problem, given by the app (not in the file)
  String? Function()? variantOf;
  String? get variant => variantOf?.call();

  List<Node> get nodes => [for (final n in (json['nodes'] as List)) Node(n as Map<String, dynamic>, variant: variant)];
  Node? node(String id) => nodes.where((n) => n.id == id).firstOrNull;

  Node addNode(LatLng position, {List<String> roles = const ['customer']}) {
    final ids = {for (final n in nodes) n.id};
    var i = ids.length + 1;
    while (ids.contains('N$i')) {
      i++;
    }
    final n = Node({
      'id': 'N$i',
      'name': 'N$i',
      'coordinates': [0, 0],
      'roles': roles,
    })..position = position;
    (json['nodes'] as List).add(n.json);
    return n;
  }

  List<Map<String, dynamic>> get _vehicles => [
    for (final v in (json['vehicles'] as List? ?? const [])) v as Map<String, dynamic>,
  ];

  /// parameters of the problems that name the node, e.g. startNode of a tsp - (problem, key)
  List<(Problem, String)> _paramRefs(String id) => [
    for (final p in problems)
      for (final MapEntry(:key, :value) in p.parameters.entries)
        if (value == id || (value is List && value.contains(id))) (p, key),
  ];

  /// where else the node is used - as message keys with arguments, for the question before deleting it
  List<(String, Map<String, Object>)> usages(String id) => [
    for (final net in networks.values)
      if (net.edges.where((e) => e.from == id || e.to == id).length case final n when n > 0)
        ('ui.use.edges', {'n': n, 'net': net.name}),
    for (final v in _vehicles)
      if (v['depot'] == id) ('ui.use.depot', {'vehicle': '${v['id']}'}),
    for (final n in nodes)
      if (n['assignedTo'] == id) ('ui.use.assigned', {'node': n.name}),
    for (final n in nodes)
      if (n['deliveryTo'] == id) ('ui.use.deliveryTo', {'node': n.name}),
    for (final (p, key) in _paramRefs(id)) ('ui.use.param', {'param': key, 'problem': p.name}),
  ];

  /// removes the node and every reference to it - edges, depots of vehicles, fixed assignments, parameters of the
  /// problems (e.g. startNode); a reference to an unknown node makes the scenario invalid
  void removeNode(String id) {
    (json['nodes'] as List).removeWhere((n) => n['id'] == id);
    for (final net in networks.values) {
      net._edges.removeWhere((e) => e['from'] == id || e['to'] == id);
    }
    for (final v in _vehicles) {
      if (v['depot'] == id) v.remove('depot');
    }
    for (final n in nodes) {
      if (n['assignedTo'] == id) n['assignedTo'] = null;
      if (n['deliveryTo'] == id) n.json.remove('deliveryTo');
    }
    for (final (p, key) in _paramRefs(id)) {
      final v = p.parameters[key];
      if (v is List) {
        v.remove(id);
      } else {
        p.parameters.remove(key);
      }
    }
  }

  /// renames a node in all references too (see removeNode)
  void renameNode(String from, String to) {
    final refs = _paramRefs(from);
    for (final n in nodes) {
      if (n.id == from) n.id = to;
      if (n['assignedTo'] == from) n['assignedTo'] = to;
      if (n['deliveryTo'] == from) n['deliveryTo'] = to;
    }
    for (final net in networks.values) {
      for (final e in net.edges) {
        if (e.from == from) e.from = to;
        if (e.to == from) e.to = to;
      }
    }
    for (final v in _vehicles) {
      if (v['depot'] == from) v['depot'] = to;
    }
    for (final (p, key) in refs) {
      final v = p.parameters[key];
      p.parameters[key] = v is List ? [for (final x in v) x == from ? to : x] : to;
    }
  }

  Map<String, Network> get networks => {
    for (final MapEntry(:key, :value) in ((json['networks'] as Map?) ?? const {}).entries)
      key as String: Network(key, value as Map<String, dynamic>, variant: variant),
  };

  Network addNetwork(String name, {bool directed = true}) {
    final nets = (json['networks'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    nets[name] = <String, dynamic>{'directed': directed, 'edges': <dynamic>[]};
    return Network(name, nets[name] as Map<String, dynamic>, variant: variant);
  }

  /// data variants - id and name; the values without a variant are the base
  List<Map<String, dynamic>> get variants => [
    for (final v in (json['variants'] as List?) ?? const []) (v as Map).cast<String, dynamic>(),
  ];

  /// a new data variant with the values of [from] (null: the base) - its id
  String addVariant(String name, {String? from}) {
    final ids = {for (final v in variants) v['id']};
    var i = ids.length + 1;
    while (ids.contains('V$i')) {
      i++;
    }
    final id = 'V$i';
    ((json['variants'] ??= <dynamic>[]) as List).add(<String, dynamic>{'id': id, 'name': name});
    if (from != null) {
      for (final item in _variantItems) {
        final all = item['variants'] as Map?;
        if (all?[from] case final Map values) all![id] = jsonDecode(jsonEncode(values));
      }
    }
    return id;
  }

  /// deletes a data variant - its values at the nodes and edges, the problems with it use the base values
  void removeVariant(String id) {
    (json['variants'] as List?)?.removeWhere((v) => (v as Map)['id'] == id);
    if ((json['variants'] as List?)?.isEmpty ?? false) json.remove('variants');
    for (final item in _variantItems) {
      final all = item['variants'] as Map?;
      all?.remove(id);
      if (all != null && all.isEmpty) item.remove('variants');
    }
    for (final p in problems.where((p) => p.variant == id)) {
      p.variant = null;
    }
  }

  /// name of a data variant - its id without name
  String variantName(String id) => variants.where((v) => v['id'] == id).map(recordName).firstOrNull ?? id;

  /// the nodes and edges (their json) that can have values of data variants
  Iterable<Map<String, dynamic>> get _variantItems sync* {
    for (final n in (json['nodes'] as List)) {
      yield n as Map<String, dynamic>;
    }
    for (final net in ((json['networks'] as Map?) ?? const {}).values) {
      for (final e in ((net as Map)['edges'] as List?) ?? const []) {
        yield e as Map<String, dynamic>;
      }
    }
  }

  /// commodities (multicommodity) and modes of transport (multimodal) - records with id, name and values
  List<Map<String, dynamic>> get commodities => _records('commodities');
  List<Map<String, dynamic>> get modes => _records('modes');
  List<Map<String, dynamic>> get vehicles => _records('vehicles');

  /// units of the distances and times, e.g. km and min
  Map<String, dynamic> get units =>
      (json['units'] ??= <String, dynamic>{'distance': 'km', 'time': 'min'}) as Map<String, dynamic>;

  List<Map<String, dynamic>> _records(String key) => ((json[key] ??= <dynamic>[]) as List).cast<Map<String, dynamic>>();

  /// name of a commodity or mode - its id without name
  static String recordName(Map<String, dynamic> r) =>
      (r['name'] as String?)?.isNotEmpty == true ? r['name'] : '${r['id']}';

  Map<String, dynamic> get matrix => (json['matrix'] ??= <String, dynamic>{}) as Map<String, dynamic>;
  bool get usesRoads => (matrix['matrixSource'] ?? 'osm') == 'osm';
  String get travelmode => matrix['travelmode'] as String? ?? 'car';

  List<Problem> get problems => [
    for (final p in (json['problems'] as List? ?? const [])) Problem(p as Map<String, dynamic>),
  ];
  Problem? problem(String name) => problems.where((p) => p.name == name).firstOrNull;

  Problem addProblem(String type, String name, Map<String, dynamic> parameters) {
    final p = Problem({'name': _freeName(name), 'type': type, 'parameters': parameters});
    ((json['problems'] ??= <dynamic>[]) as List).add(p.json);
    return p;
  }

  /// the name - with a number if a problem has it already
  String _freeName(String name) {
    final names = {for (final p in problems) p.name};
    var n = name;
    for (var i = 2; names.contains(n); i++) {
      n = '$name $i';
    }
    return n;
  }

  /// a copy of the problem (its parameters and network) behind it - named name
  Problem duplicateProblem(String of, String name) {
    final list = json['problems'] as List;
    final i = list.indexWhere((p) => (p as Map)['name'] == of);
    final copy = Problem(jsonDecode(jsonEncode(list[i])) as Map<String, dynamic>)..name = _freeName(name);
    list.insert(i + 1, copy.json);
    return copy;
  }

  /// the problem out of the scenario - the nodes, edges and networks stay
  void removeProblem(String name) => (json['problems'] as List?)?.removeWhere((p) => (p as Map)['name'] == name);
}
