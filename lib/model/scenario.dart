/// Scenario file (.llab) of LogisticsLab - see pyLogisticsLab/docs/dateiformate.md.
///
/// The app works on the JSON of the file: fields it does not know (yet) are kept and written back unchanged.
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';

const nodeRoles = ['supplier', 'customer', 'candidate', 'depot', 'transit'];

class Node {
  final Map<String, dynamic> json;
  Node(this.json);

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

  /// attribute of a problem type, e.g. supply - null removes it from the file
  Object? operator [](String key) => json[key];
  void operator []=(String key, Object? v) => v == null ? json.remove(key) : json[key] = v;

  static double _round(double v) => (v * 1e6).roundToDouble() / 1e6;
}

class Edge {
  final Map<String, dynamic> json;
  Edge(this.json);
  String get from => json['from'] as String;
  String get to => json['to'] as String;
}

class Network {
  final String name;
  final Map<String, dynamic> json;
  Network(this.name, this.json);

  bool get directed => json['directed'] as bool? ?? false;
  List<Edge> get edges => [for (final e in (json['edges'] as List? ?? const [])) Edge(e as Map<String, dynamic>)];
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

  factory Scenario.empty() => Scenario({
    'format': 'logisticsLab',
    'version': 1,
    'id': 'scenario',
    'name': '',
    'units': {'distance': 'km', 'time': 'min'},
    'matrix': {'matrixSource': 'osm', 'travelmode': 'car'},
    'nodes': <dynamic>[],
    'problems': <dynamic>[],
  });

  String toText() => '${const JsonEncoder.withIndent('  ').convert(json)}\n';

  String get id => json['id'] as String? ?? 'scenario';
  String? get name => json['name'] as String?;

  List<Node> get nodes => [for (final n in (json['nodes'] as List)) Node(n as Map<String, dynamic>)];
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

  void removeNode(String id) => (json['nodes'] as List).removeWhere((n) => n['id'] == id);

  /// renames a node in the edges and assignments too
  void renameNode(String from, String to) {
    for (final n in nodes) {
      if (n.id == from) n.id = to;
      if (n['assignedTo'] == from) n['assignedTo'] = to;
    }
    for (final net in networks.values) {
      for (final e in net.edges) {
        if (e.json['from'] == from) e.json['from'] = to;
        if (e.json['to'] == from) e.json['to'] = to;
      }
    }
  }

  Map<String, Network> get networks => {
    for (final MapEntry(:key, :value) in ((json['networks'] as Map?) ?? const {}).entries)
      key as String: Network(key, value as Map<String, dynamic>),
  };

  Map<String, dynamic> get matrix => (json['matrix'] ??= <String, dynamic>{}) as Map<String, dynamic>;
  bool get usesRoads => (matrix['matrixSource'] ?? 'osm') == 'osm';
  String get travelmode => matrix['travelmode'] as String? ?? 'car';

  List<Problem> get problems => [
    for (final p in (json['problems'] as List? ?? const [])) Problem(p as Map<String, dynamic>),
  ];
  Problem? problem(String name) => problems.where((p) => p.name == name).firstOrNull;

  Problem addProblem(String type, String name, Map<String, dynamic> parameters) {
    final names = {for (final p in problems) p.name};
    var n = name;
    for (var i = 2; names.contains(n); i++) {
      n = '$name $i';
    }
    final p = Problem({'name': n, 'type': type, 'parameters': parameters});
    ((json['problems'] ??= <dynamic>[]) as List).add(p.json);
    return p;
  }
}
