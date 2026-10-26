/// State of the app: the open scenario, the chosen problem and node, the solutions and the computing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend/backend.dart';
import 'i18n/strings.dart';
import 'model/clock.dart';
import 'model/scenario.dart';
import 'model/solution_analysis.dart';
import 'modules/modules.dart';

enum DataTab { nodes, network, parameters, solution }

/// Solution document (llsol) of a problem and the revision of the data it was computed with.
class SolutionState {
  final Map<String, dynamic> document;
  final int revision;
  SolutionState(this.document, this.revision);

  String get status => document['status'] as String? ?? 'error';
  Map<String, dynamic>? get results => document['results'] as Map<String, dynamic>?;
}

class AppState extends ChangeNotifier {
  AppState(this.strings, this._prefs) {
    _backendSettings = _loadBackendSettings();
    splitRatio = _prefs.getDouble('splitRatio') ?? defaultSplitRatio;
    listRatio = _prefs.getDouble('listRatio') ?? defaultListRatio;
  }

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final strings = await Strings.load(prefs.getString('language') ?? systemLanguage());
    return AppState(strings, prefs);
  }

  final SharedPreferences _prefs;
  Strings strings;

  //*********** settings ************

  static const defaultSplitRatio = 0.6;
  late double splitRatio; // part of the map - the rest is the data area

  static const defaultListRatio = 0.5;
  late double listRatio; // part of the list in the nodes and network tab - the rest is the mask

  void setListRatio(double v, {bool save = false}) {
    listRatio = v.clamp(0.15, 0.85);
    if (save) _prefs.setDouble('listRatio', listRatio);
    notifyListeners();
  }

  /// wide view of the data area (large solutions): the map narrow - again: the width before
  static const wideRatio = 0.3;
  double? _narrowRatio;
  bool get wideData => splitRatio <= wideRatio + 0.01;

  void toggleWideData() {
    if (wideData) {
      setSplitRatio(_narrowRatio ?? defaultSplitRatio, save: true);
    } else {
      _narrowRatio = splitRatio;
      setSplitRatio(wideRatio, save: true);
    }
  }

  void setSplitRatio(double v, {bool save = false}) {
    splitRatio = v.clamp(0.25, 0.8);
    if (save) _prefs.setDouble('splitRatio', splitRatio);
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    if (language == strings.language) return;
    strings = await Strings.load(language);
    await _prefs.setString('language', language);
    notifyListeners();
  }

  late BackendSettings _backendSettings;
  BackendSettings get backendSettings => _backendSettings;

  BackendSettings _loadBackendSettings() {
    final d = defaultBackendSettings();
    // no program saved: the default (environment or the solver bundled with the app) - it follows the app
    final exe = _prefs.getString('backend.executable') ?? '';
    final args = _prefs.getString('backend.arguments');
    return BackendSettings(
      remote: !localBackendSupported || (_prefs.getBool('backend.remote') ?? d.remote),
      executable: exe.isEmpty ? d.executable : exe,
      arguments: exe.isEmpty || args == null ? d.arguments : (jsonDecode(args) as List).cast<String>(),
      workingDirectory: exe.isEmpty ? d.workingDirectory : _prefs.getString('backend.workingDirectory') ?? '',
      url: _prefs.getString('backend.url') ?? d.url,
      apiKey: _prefs.getString('backend.apiKey') ?? d.apiKey,
    );
  }

  Future<void> setBackendSettings(BackendSettings s) async {
    _backendSettings = s;
    final d = defaultBackendSettings();
    final isDefault =
        s.executable == d.executable &&
        s.workingDirectory == d.workingDirectory &&
        listEquals(s.arguments, d.arguments);
    await _prefs.setBool('backend.remote', s.remote);
    await _prefs.setString('backend.executable', isDefault ? '' : s.executable);
    await _prefs.setString('backend.arguments', jsonEncode(isDefault ? const <String>[] : s.arguments));
    await _prefs.setString('backend.workingDirectory', isDefault ? '' : s.workingDirectory);
    await _prefs.setString('backend.url', s.url);
    await _prefs.setString('backend.apiKey', s.apiKey);
    await _closeBackend();
    _routeFailures.clear(); // a new solver or server - courses given up are tried again
    notifyListeners();
  }

  //*********** scenario ************

  Scenario scenario = Scenario.empty();
  int opened = 0; // counts the opened scenarios
  int geometry = 0; // changes with the nodes or their coordinates - the map then shows all nodes
  int clickedGeometry = -1; // geometry after a click into the map - in view already, the map keeps its section
  String? fileName; // shown in the header
  String? filePath; // desktop: Save writes there
  bool dirty = false;
  int revision = 0; // changed with every edit - a solution of an older revision is stale

  String? problemName;
  String? selectedNode;
  DataTab tab = DataTab.nodes;
  bool placing = false; // next tap into the map sets the position of the selected node
  bool addingNodes = false; // every tap into the map adds a node - until it is switched off
  final solutions = <String, SolutionState>{};

  Problem? get problem => problemName == null ? null : scenario.problem(problemName!);
  ModuleSpec? get spec => modules[problem?.type];
  Node? get node => selectedNode == null ? null : scenario.node(selectedNode!);
  SolutionState? get solution => problemName == null ? null : solutions[problemName];

  /// roles of the nodes used by the problem - all roles without a problem (type)
  List<String> get problemRoles => spec?.problemRoles(problem?.parameters ?? const {}) ?? nodeRoles;

  /// active and with a role in the problem - other nodes are pale in the list and on the map
  bool isRelevant(Node n) =>
      n.active &&
      (spec?.allNodes == true ||
          n.roles.any(problemRoles.contains) ||
          (spec?.network == NetworkUse.required && _inNetwork(n.id)));

  /// a value of the solution in its unit - costs with two decimals and €, else with the unit (km, min)
  String valueText(num v) {
    final unit = solution?.document['valueUnit'] as String?;
    return unit == null || unit == 'costs' ? '${strings.fixed(v, 2)} €' : '${strings.number(v)} $unit';
  }

  /// roles of a node for its symbol on the map - those of the problem; a tsp: the start like a supplier (square),
  /// the other stops like customers (circle)
  List<String> symbolRoles(Node n) {
    if (spec?.allNodes == true) {
      // the start only if the tour has a fixed one
      final p = problem?.parameters ?? const <String, dynamic>{};
      final start = const ['openStart', 'free'].contains(p['tourType']) ? null : p['startNode'];
      return [n.id == start ? 'supplier' : 'customer'];
    }
    // chinese postman: the start like a supplier, the other nodes of the network are transit
    if (spec?.type == 'cpp') return n.id == problem!.parameters['startNode'] ? const ['supplier'] : const [];
    // shortest way: start like a supplier, end like a customer, the other nodes of the network are transit
    if (spec?.type == 'shortestpath') {
      final p = problem!.parameters;
      return n.id == p['startNode'] ? ['supplier'] : (n.id == p['endNode'] ? ['customer'] : const []);
    }
    return [
      for (final r in n.roles)
        if (problemRoles.contains(r)) r,
    ];
  }

  /// nodes a section of a tour passes on its shortest way through the network - "über A, B", empty without
  String via(Map<String, dynamic> leg) {
    final path = (leg['path'] as List?)?.cast<String>() ?? const [];
    if (path.length < 3) return '';
    return strings('ui.sol.via', {
      'nodes': [for (final id in path.sublist(1, path.length - 1)) scenario.node(id)?.name ?? id].join(', '),
    });
  }

  /// times of the day in the time unit of the scenario
  Clock get clock => Clock(scenario.units['time'] as String? ?? 'min');

  /// the tours of a solution with several vehicles (vrp): "Tour 1 · LKW1", ...
  List<String> get routeNames => [
    for (final (i, r) in ((solution?.results?['routes'] as List?) ?? const []).cast<Map<String, dynamic>>().indexed)
      [
        strings('ui.sol.tour', {'n': i + 1}),
        if (r['vehicle'] != null) '${r['vehicle']}',
      ].join(' · '),
  ];

  /// the solution consists of tours (tsp) - its connections are the sections of the tours
  bool get isRoute => solution?.results?['routes'] != null;

  /// node of the network of the problem - network flows use every node of it, also transit nodes
  bool _inNetwork(String id) => network?.edges.any((e) => e.from == id || e.to == id) ?? false;

  /// split of a connection per commodity (multicommodity: flows) or mode (multimodal: modes) - "Bahn 75", empty
  /// without split
  String split(Map<String, dynamic> connection) {
    String part(String key, List<Map<String, dynamic>> records) {
      final values = (connection[key] as Map?)?.cast<String, dynamic>() ?? const {};
      return [
        for (final MapEntry(:key, :value) in values.entries)
          '${Scenario.recordName(records.firstWhere((r) => r['id'] == key, orElse: () => {'id': key}))} ${strings.number(value as num)}',
      ].join(' · ');
    }

    return [part('flows', scenario.commodities), part('modes', scenario.modes)].where((p) => p.isNotEmpty).join(' · ');
  }

  /// the data of a node in the problem: the visible fields of its roles with a value, e.g. demand, service time and
  /// time window of a customer
  List<(FieldSpec, String)> nodeData(Node n) {
    final spec = this.spec;
    if (spec == null) return const [];
    final params = problem?.parameters ?? const <String, dynamic>{};
    final seen = <String>{};
    return [
      for (final r in spec.activeRoles(params))
        if (n.roles.contains(spec.nodeRole(r, params)))
          for (final f in r.nodeFields)
            if (f.kind != FieldKind.boolean && f.isVisible(params) && seen.add(f.key))
              if (nodeFieldText(n, f) case final String v when v.isNotEmpty) (f, v),
    ];
  }

  /// pickup and delivery: the active pickups that bring their amount to the node - (pickup, amount)
  List<(Node, num)> deliveries(Node n) => [
    for (final p in scenario.nodes)
      if (p.active && p['deliveryTo'] == n.id && p.roles.contains('pickup')) (p, p['amount'] as num? ?? 0),
  ];

  /// value of a field of a node as text - time windows as times of the day, durations and distances with their unit
  String? nodeFieldText(Node n, FieldSpec f) {
    if (f.key == 'delivered') {
      final q = deliveries(n);
      return q.isEmpty ? null : strings.number(q.fold<num>(0, (sum, e) => sum + e.$2));
    }
    final v = n[f.key] ?? f.defaultValue;
    if (f.kind == FieldKind.timeWindow && v is List) {
      return '${clock.format(v[0] as num?)} – ${clock.format(v.length > 1 ? v[1] as num? : null)}';
    }
    // another node: its name
    if (f.kind == FieldKind.node) return v == null ? null : scenario.node('$v')?.name ?? '$v';
    final text = fieldText(v);
    final unit = switch (f.unit) {
      '@time' => scenario.units['time'] as String?,
      '@distance' => scenario.units['distance'] as String?,
      final u => u,
    };
    return text == null || unit == null || unit == '€' ? text : '$text $unit';
  }

  /// value of a field as text - numbers, 'M' (unlimited), values per commodity (sum), modes (names); null: empty
  String? fieldText(Object? v) {
    if (v == null) return null;
    // time window: earliest – latest
    if (v is List) {
      String part(Object? x) => x is num ? strings.number(x) : '';
      return '${part(v[0])} – ${part(v.length > 1 ? v[1] : null)}';
    }
    if (v == 'M') return '∞';
    if (v is num) return strings.number(v);
    if (v is Map) {
      // modes of an edge: their names; values per commodity: the sum
      if (v.values.every((x) => x is Map)) {
        return [
          for (final id in v.keys)
            Scenario.recordName(scenario.modes.firstWhere((m) => m['id'] == id, orElse: () => {'id': id})),
        ].join(', ');
      }
      final sum = SolutionAnalysis.total(v);
      return sum == null ? null : strings.number(sum);
    }
    return '$v';
  }

  /// total demand of the customers of the problem - an empty demand counts as 1 (location problems)
  num get totalDemand {
    final s = spec, p = problem;
    if (s == null || p == null) return 0;
    final role = s.nodeRole(s.roles.last, p.parameters);
    return scenario.nodes
        .where((n) => n.active && n.roles.contains(role))
        .fold<num>(0, (sum, n) => sum + (n['demand'] as num? ?? 1));
  }

  /// continuous location with capacities: the smallest capacity per location for the total demand and p
  num? get minCapacity {
    final n = problem?.parameters['p'];
    if (spec?.group != ModuleGroup.location || spec!.roles.first.defaultRole == 'candidate') return null;
    if (n is! int || n < 1) return null;
    return (totalDemand / n).ceil();
  }

  /// continuous location: the locations found - not nodes of the scenario - id (F1, ...) -> position
  Map<String, LatLng> get foundLocations => {
    for (final MapEntry(:key, :value) in ((solution?.results?['nodes'] as Map?) ?? const {}).entries)
      if ((value as Map)['coordinates'] case [final num lat, final num lon] when scenario.node('$key') == null)
        key as String: LatLng(lat.toDouble(), lon.toDouble()),
  };

  /// position of a node of the scenario or of a location found
  LatLng? positionOf(String id) => scenario.node(id)?.position ?? foundLocations[id];

  /// name of a node of the scenario or of a location found ("Standort 1")
  String nameOf(String id) =>
      scenario.node(id)?.name ??
      (foundLocations.containsKey(id) ? strings('ui.sol.foundLocation', {'n': id.replaceAll(RegExp(r'\D'), '')}) : id);

  /// the locations found become candidates - e.g. for a warehouse location problem afterwards
  void adoptFoundLocations() => edit(() {
    for (final MapEntry(:key, :value) in foundLocations.entries) {
      final n = scenario.addNode(value, roles: const ['candidate']);
      n.name = nameOf(key);
    }
  });

  /// warehouses of the solution (multistagewlp): id -> open
  Map<String, bool> get openNodes => {
    for (final MapEntry(:key, :value) in ((solution?.results?['nodes'] as Map?) ?? const {}).entries)
      if ((value as Map)['open'] != null) key as String: value['open'] == 1,
  };

  /// connections of the solution of the problem - tpp: assignments, network flows: edges
  /// rates of the connections are contributions (tpp max) instead of costs
  bool get ratesAreContributions => (solution?.results?['summary'] as Map?)?.containsKey('totalContribution') ?? false;

  /// labels of the rate and the value of a connection: cost rate and costs, or contribution per unit and contribution
  (String, String) get rateLabels => ratesAreContributions
      ? (strings('result.contributionRate'), strings('ui.sol.contribution'))
      : (strings('result.rate'), strings('ui.sol.costs'));

  List<Map<String, dynamic>> get connections => SolutionAnalysis.connectionsOf(solution?.results, solutionPart);

  /// commodity (multicommodity) or mode (multimodal) the solution shows - null: all together
  String? solutionPart;

  /// commodities or modes of the problem the solution can show one by one
  List<Map<String, dynamic>> get solutionParts => spec?.usesCommodities == true
      ? scenario.commodities
      : spec?.usesModes == true
      ? scenario.modes
      : const [];

  void setSolutionPart(String? part) {
    solutionPart = part;
    selectedFlow = null; // the indexes of the connections change
    selectedRoute = null;
    highlightedNode = null;
    notifyListeners();
  }

  /// how the nodes are served in the solution of the problem (shares, partners) - null without solution
  /// supply shipped and demand met - not for locations (their customers are assigned, not supplied)
  SolutionAnalysis? get analysis => spec?.group == ModuleGroup.location
      ? null
      : SolutionAnalysis.of(
          scenario,
          spec,
          problem?.parameters ?? const {},
          solution?.results,
          networkNodes: spec?.network == NetworkUse.required ? networkNodeIds : const [],
          part: spec?.usesCommodities == true ? solutionPart : null, // modes: the nodes have no values per mode
        );

  /// deletes a commodity or mode of the scenario and its values at the nodes and edges
  void deleteRecord(String kind, Map<String, dynamic> record) => edit(() {
    final id = record['id'];
    (switch (kind) {
      'commodities' => scenario.commodities,
      'vehicles' => scenario.vehicles,
      _ => scenario.modes,
    }).remove(record);
    if (kind == 'vehicles') return;
    final edges = [for (final net in scenario.networks.values) ...net.edges];
    if (kind == 'commodities') {
      for (final n in scenario.nodes) {
        for (final key in const ['supplies', 'demands', 'capacityFactors']) {
          if (n[key] case final Map m) {
            m.remove(id);
            if (m.isEmpty) n.json.remove(key);
          }
        }
      }
      for (final e in edges) {
        if (e.json['commodities'] case final Map m) {
          m.remove(id);
          if (m.isEmpty) e.json.remove('commodities');
        }
      }
      for (final p in scenario.problems) {
        (p.parameters['commodities'] as List?)?.remove(id);
      }
    } else {
      // an edge keeps its other modes - without one it is closed, as before
      for (final e in edges) {
        (e.json['modes'] as Map?)?.remove(id);
      }
    }
    if (solutionPart == id) solutionPart = null;
  });

  /// missing or wrong values of the nodes of the problem (e.g. supply of a tpp) and roles without nodes - one
  /// message per field, checked before solving
  List<String> get nodeProblems {
    final s = spec, p = problem;
    if (s == null || p == null) return const [];
    String names(List<Node> nodes) => [
      for (final n in nodes.take(5)) n.name,
      if (nodes.length > 5) strings('ui.check.more', {'n': nodes.length - 5}),
    ].join(', ');
    final out = <String>[];
    // data of the scenario the problem needs
    if (s.usesCommodities && scenario.commodities.isEmpty) out.add(strings('ui.commodities.none'));
    if (s.usesModes && scenario.modes.isEmpty) out.add(strings('ui.modes.none'));
    if (s.usesVehicles) {
      if (scenario.vehicles.isEmpty) out.add(strings('ui.vehicles.none'));
      final noCapacity = [
        for (final v in scenario.vehicles)
          if (v['capacity'] is! num) Scenario.recordName(v),
      ];
      if (noCapacity.isNotEmpty) out.add(strings('ui.check.vehicleCapacity', {'vehicles': noCapacity.join(', ')}));
      final depots = [
        for (final n in scenario.nodes)
          if (n.active && n.roles.contains('depot')) n.name,
      ];
      if (depots.length > 1) out.add(strings('ui.check.oneDepot', {'nodes': depots.join(', ')}));
    }
    if (s.network == NetworkUse.required && network != null && network!.edges.isEmpty) {
      out.add(strings('ui.check.noEdges'));
    }
    if (s.allNodes && scenario.nodes.where((n) => n.active).length < 2) out.add(strings('ui.check.twoNodes'));
    final matrix = scenario.matrix;
    if (p.parameters['matrixMode'] == 'costs' && matrix['costPerKm'] == null && matrix['costPerHour'] == null) {
      out.add(strings('ui.check.costRates'));
    }
    // nodes of the parameters (start, end, source, sink): active nodes of the scenario
    for (final f in s.visibleParameters(p.parameters).where((f) => f.kind == FieldKind.node)) {
      final id = p.parameters[f.key];
      if (id == null) continue; // required: checked with the parameters
      final n = scenario.node('$id');
      if (n == null || !n.active) out.add(strings('ui.check.nodeParam', {'field': strings(f.label), 'node': '$id'}));
    }
    // capacities of the locations: enough for the total demand
    if (s.group == ModuleGroup.location && p.parameters['isCapacitated'] == true) {
      final total = totalDemand;
      final candidates = s.roles.first.defaultRole == 'candidate';
      if (!candidates) {
        // continuous location: one capacity for the p locations
        final cap = p.parameters['capacities'];
        if (minCapacity case final min? when cap is num && cap < min) {
          out.add(
            strings('ui.check.capacityPerLocation', {'min': strings.number(min), 'total': strings.number(total)}),
          );
        }
      } else {
        // the capacities of the candidates - p-median and p-centre: the p largest
        final role = s.nodeRole(s.roles.first, p.parameters);
        final caps = [
          for (final x in scenario.nodes)
            if (x.active && x.roles.contains(role)) x['capacity'] is num ? (x['capacity'] as num) : double.infinity,
        ]..sort((a, b) => b.compareTo(a));
        final n = p.parameters['p'] is int ? p.parameters['p'] as int : caps.length;
        final sum = caps.take(n).fold<num>(0, (a, b) => a + b);
        if (sum < total) {
          out.add(strings('ui.check.capacities', {'sum': strings.number(sum), 'total': strings.number(total)}));
        }
      }
    }
    // p-median, p-centre: at most as many locations as candidates
    if (p.parameters['p'] case final int n
        when s.group == ModuleGroup.location && s.roles.first.defaultRole == 'candidate') {
      final role = s.nodeRole(s.roles.first, p.parameters);
      final candidates = scenario.nodes.where((x) => x.active && x.roles.contains(role)).length;
      if (n > candidates) out.add(strings('ui.check.tooManyLocations', {'p': n, 'n': candidates}));
    }
    // pickup and delivery: the delivery node of every pickup - a node with the role delivery
    if (s.type == 'pdp') {
      final deliveries = s.nodeRole(s.roles.last, p.parameters);
      final pickups = [
        for (final n in scenario.nodes)
          if (n.active && n.roles.contains(s.nodeRole(s.roles[1], p.parameters))) n,
      ];
      final wrong = [
        for (final n in pickups)
          if (n['deliveryTo'] != null && !(scenario.node('${n['deliveryTo']}')?.roles.contains(deliveries) ?? false)) n,
      ];
      if (wrong.isNotEmpty) out.add(strings('ui.check.deliveryTo', {'nodes': names(wrong)}));
    }
    for (final r in s.activeRoles(p.parameters)) {
      final role = s.nodeRole(r, p.parameters);
      final nodes = [
        for (final n in scenario.nodes)
          if (n.active && n.roles.contains(role)) n,
      ];
      if (nodes.isEmpty) {
        out.add(strings('ui.check.noNodes', {'role': strings('role.$role.plural')}));
        continue;
      }
      // one role per problem - a node with two of them (e.g. from an old file)
      if (r == s.activeRoles(p.parameters).first) {
        final roles = problemRoles;
        final multiple = [
          for (final n in scenario.nodes)
            if (n.active && n.roles.where(roles.contains).length > 1) n,
        ];
        if (multiple.isNotEmpty) out.add(strings('ui.check.multipleRoles', {'nodes': names(multiple)}));
      }
      for (final f in r.nodeFields.where((f) => f.isVisible(p.parameters))) {
        final missing = [
          for (final n in nodes)
            if (f.required && (n[f.key] ?? f.defaultValue) == null) n,
        ];
        final wrong = [
          for (final n in nodes)
            if ((n[f.key] ?? f.defaultValue) != null && f.validate(n[f.key] ?? f.defaultValue) != null) n,
        ];
        final label = strings(f.label);
        if (missing.isNotEmpty) out.add(strings('ui.check.missing', {'field': label, 'nodes': names(missing)}));
        if (wrong.isNotEmpty) out.add(strings('ui.check.wrong', {'field': label, 'nodes': names(wrong)}));
      }
    }
    return out;
  }

  /// nodes of the network of the problem in the order of the scenario
  List<String> get networkNodeIds => [
    for (final n in scenario.nodes)
      if (_inNetwork(n.id)) n.id,
  ];

  bool get solutionIsStale => solution != null && solution!.revision != revision;

  void openScenario(Scenario s, {String? name, String? path}) {
    scenario = s;
    opened++;
    geometry++;
    fileName = name;
    filePath = path;
    dirty = false;
    revision++;
    solutions.clear();
    final first = s.problems.where((p) => modules.containsKey(p.type)).firstOrNull ?? s.problems.firstOrNull;
    problemName = first?.name;
    selectedNode = s.nodes.firstOrNull?.id;
    nodeFilter = null;
    selectedEdge = null;
    drawingEdge = false;
    edgeStart = null;
    selectedFlow = null;
    selectedRoute = null;
    highlightedNode = null;
    tab = DataTab.nodes;
    placing = false;
    message = null;
    notifyListeners();
  }

  void saved({required String name, String? path}) {
    fileName = name;
    filePath = path ?? filePath;
    dirty = false;
    notifyListeners();
  }

  /// every change of the data goes through here
  void edit(void Function() change) {
    final before = _coordinates();
    change();
    if (_coordinates() != before) geometry++;
    _keepSelectionVisible();
    dirty = true;
    revision++;
    notifyListeners();
  }

  String _coordinates() => [for (final n in scenario.nodes) n.json['coordinates']].join(';');

  void chooseProblem(String name) {
    problemName = name;
    selectedFlow = null;
    selectedRoute = null;
    highlightedNode = null;
    solutionPart = null;
    selectedEdge = null;
    drawingEdge = false;
    if (nodeFilter != null &&
        nodeFilter!.isNotEmpty &&
        nodeFilter != transitFilter &&
        !problemRoles.contains(nodeFilter)) {
      nodeFilter = null;
    }
    _keepSelectionVisible();
    notifyListeners();
  }

  //*********** solution ************

  int? selectedFlow; // index in the connections (assignments) of the solution - highlighted on the map

  /// [showTab]: chosen on the map - the solution tab shows the connection
  void selectFlow(int? i, {bool showTab = false}) {
    selectedFlow = i == selectedFlow ? null : i; // a second tap removes the highlight
    if (showTab && selectedFlow != null) tab = DataTab.solution;
    if (selectedFlow != null) {
      selectedEdge = null; // only one highlight on the map
      selectedRoute = null;
      highlightedNode = null;
    }
    notifyListeners();
  }

  int? selectedRoute; // a whole tour of the solution (vrp) - all its sections highlighted on the map

  /// a node of the solution (supplier, location) - all its connections highlighted, until one connection is chosen
  String? highlightedNode;

  /// the connection touches the highlighted node
  bool touchesHighlighted(Map<String, dynamic> a) =>
      highlightedNode != null && (a['from'] == highlightedNode || a['to'] == highlightedNode);

  /// highlights the connections of a node - a second tap removes it
  void highlightNode(String? id) {
    highlightedNode = id == highlightedNode ? null : id;
    if (highlightedNode != null) {
      selectedFlow = null;
      selectedRoute = null;
      selectedEdge = null;
      selectedNode = highlightedNode;
    }
    notifyListeners();
  }

  /// a tour of the overview: highlighted on the map, a second tap removes it - instead of a section or an edge
  void selectRoute(int? r) {
    selectedRoute = r == selectedRoute ? null : r;
    if (selectedRoute != null) {
      selectedFlow = null;
      selectedEdge = null;
    }
    notifyListeners();
  }

  //*********** network and edges ************

  int? selectedEdge; // index in the edges of the network of the problem
  bool drawingEdge = false; // map: the next two nodes tapped are the ends of a new edge
  String? edgeStart;

  Network? get network {
    final name = problem?.network;
    return name == null ? null : scenario.networks[name];
  }

  Edge? get edge {
    final edges = network?.edges ?? const <Edge>[];
    final i = selectedEdge;
    return i == null || i >= edges.length ? null : edges[i];
  }

  /// new network of the problem - directed: the edges are only allowed from -> to
  void newNetwork(String name, {bool directed = true}) {
    final p = problem;
    if (p == null || name.trim().isEmpty || scenario.networks.containsKey(name.trim())) return;
    edit(() {
      scenario.addNetwork(name.trim(), directed: directed);
      p.network = name.trim();
      selectedEdge = null;
      tab = DataTab.network;
    });
  }

  void chooseNetwork(String? name) => edit(() {
    problem?.network = name;
    selectedEdge = null;
  });

  /// false if the edge exists already or both ends are the same node
  /// null if the edge from -> to is allowed, else the message key why not
  String? edgeProblem(String from, String to) {
    final net = network;
    if (net == null) return 'ui.net.required';
    if (from == to || net.hasEdge(from, to)) return 'ui.edge.exists';
    if (!edgeAllowed(from, to)) return 'ui.edge.direction';
    return null;
  }

  /// new edge - in a transport problem against its direction it is turned round; false if not allowed (see
  /// edgeProblem)
  bool addEdge(String from, String to) {
    final net = network;
    if (net == null) return false;
    if (!edgeAllowed(from, to) && edgeAllowed(to, from)) (from, to) = (to, from);
    if (edgeProblem(from, to) != null) return false;
    edit(() {
      _directed(net.addEdge(from, to), net);
      selectedEdge = net.edges.length - 1;
      tab = DataTab.network;
    });
    return true;
  }

  /// edges of a transport problem lead one way - in an undirected network the edge itself is directed
  void _directed(Edge e, Network net) {
    if (isTransport && !net.directed) e['directed'] = true;
  }

  //*********** direction of the edges of transport problems ************

  /// transport problems (tpp, network flows): the edges lead from the suppliers over the transshipment nodes to the
  /// customers
  bool get isTransport =>
      spec != null && (spec!.type == 'tpp' || (spec!.group == ModuleGroup.network && spec!.type != 'shortestpath'));

  /// stage of a node in a transport problem: 0 sends (supplier, source), 1 passes through (transshipment node,
  /// warehouse), 2 receives (customer, sink) - null: sends and receives
  int? stageOf(String id) {
    final n = scenario.node(id);
    final s = spec;
    if (n == null || s == null) return null;
    final p = problem?.parameters ?? const <String, dynamic>{};
    final roles = s.activeRoles(p);
    if (roles.length < 2) {
      // max flow with one source and one sink
      return id == p['source'] ? 0 : (id == p['sink'] ? 2 : 1);
    }
    final sends = n.roles.contains(s.nodeRole(roles.first, p));
    final receives = n.roles.contains(s.nodeRole(roles.last, p));
    if (sends && receives) return null;
    return sends ? 0 : (receives ? 2 : 1);
  }

  /// direction of an edge in a transport problem: not into a sender and not out of a receiver - tpp: only from a
  /// supplier to a customer; other problems: every edge
  bool edgeAllowed(String from, String to) {
    if (!isTransport) return true;
    final a = stageOf(from), b = stageOf(to);
    if (spec!.type == 'tpp') return (a == 0 || a == null) && (b == 2 || b == null);
    if (a == null || b == null) return true;
    return a != 2 && b != 0;
  }

  /// tsp, shortest path: every active node with every other - one edge per pair in an undirected network, both
  /// directions in a directed one
  int _connectAll(Network net) {
    final ids = [
      for (final n in scenario.nodes)
        if (n.active) n.id,
    ];
    var count = 0;
    edit(() {
      for (var i = 0; i < ids.length; i++) {
        for (var j = 0; j < ids.length; j++) {
          if (i == j || (!net.directed && j < i)) continue;
          if (!net.hasEdge(ids[i], ids[j])) {
            net.addEdge(ids[i], ids[j]);
            count++;
          }
        }
      }
    });
    return count;
  }

  /// transshipment nodes for new edges of a network flow: nodes with the role transit or candidate (warehouse)
  /// that neither send nor receive
  List<String> get transitCandidates => [
    if (spec?.group == ModuleGroup.network)
      for (final n in scenario.nodes)
        if (n.active && (n.roles.contains('transit') || n.roles.contains('candidate')) && stageOf(n.id) == 1) n.id,
  ];

  /// the missing edges of a transport problem: senders -> transshipment nodes -> receivers, without transshipment
  /// nodes senders -> receivers (tpp: suppliers -> customers) - returns the number of new edges
  int addAllEdges() {
    final net = network;
    final params = problem?.parameters ?? const <String, dynamic>{};
    final roles = spec?.activeRoles(params) ?? const <RoleSpec>[];
    if (net != null && spec?.edgeDirections == true) return _connectAll(net);
    if (net == null || roles.length < 2) return 0;
    List<String> stage(int k) => [
      for (final n in scenario.nodes)
        if (n.active && stageOf(n.id) == k) n.id,
    ];
    final senders = stage(0), receivers = stage(2), middle = transitCandidates;
    final steps = middle.isEmpty ? [(senders, receivers)] : [(senders, middle), (middle, receivers)];
    var count = 0;
    edit(() {
      for (final (from, to) in steps) {
        for (final a in from) {
          for (final b in to) {
            if (a != b && !net.hasEdge(a, b)) {
              _directed(net.addEdge(a, b), net);
              count++;
            }
          }
        }
      }
    });
    return count;
  }

  void deleteEdge() {
    final net = network;
    final i = selectedEdge;
    if (net == null || i == null || i >= net.edges.length) return;
    edit(() {
      net.removeEdgeAt(i);
      final n = net.edges.length;
      selectedEdge = n == 0 ? null : i.clamp(0, n - 1);
    });
  }

  /// [showTab]: chosen on the map - the network tab shows the edge in its mask
  void selectEdge(int? i, {bool showTab = false}) {
    selectedEdge = i;
    if (showTab && i != null) tab = DataTab.network;
    if (i != null) {
      selectedFlow = null; // only one highlight on the map
      selectedRoute = null;
      highlightedNode = null;
    }
    notifyListeners();
  }

  void setDrawingEdge(bool v) {
    drawingEdge = v && network != null;
    edgeStart = null;
    placing = false;
    if (drawingEdge) addingNodes = false;
    notifyListeners();
  }

  /// a node tapped on the map: selection, or an end of the edge being drawn - returns the message key if the edge
  /// is not allowed
  String? tapNode(String id) {
    if (!drawingEdge) {
      // the solution shown: the connections of the node - else the node in its list
      if (tab == DataTab.solution && connections.any((a) => a['from'] == id || a['to'] == id)) {
        highlightNode(id);
      } else {
        selectNode(id);
      }
      return null;
    }
    if (edgeStart == null) {
      edgeStart = id;
      notifyListeners();
      return null;
    }
    final start = edgeStart!;
    drawingEdge = false;
    edgeStart = null;
    if (addEdge(start, id)) return null;
    notifyListeners();
    return edgeProblem(start, id) ?? edgeProblem(id, start);
  }

  //*********** filter of the node list ************

  /// null: all nodes, '': nodes without a role in the problem, transitFilter: transshipment nodes of a network flow,
  /// else a role of the problem
  String? nodeFilter;

  static const transitFilter = '@transit';

  /// network flow: nodes of its network without a role of the problem pass quantities through
  bool isTransit(Node n) =>
      spec?.network == NetworkUse.required && !n.roles.any(problemRoles.contains) && _inNetwork(n.id);

  bool _passes(Node n, String? filter) => filter == null
      ? true
      : filter == transitFilter
      ? isTransit(n)
      : filter.isEmpty
      ? !n.roles.any(problemRoles.contains) && !isTransit(n)
      : n.roles.contains(filter);

  List<Node> nodesOf(String? filter) => [
    for (final n in scenario.nodes)
      if (_passes(n, filter)) n,
  ];

  List<Node> get filteredNodes => nodesOf(nodeFilter);

  void setNodeFilter(String? filter) {
    nodeFilter = filter;
    // the selection stays in the list
    final shown = filteredNodes;
    if (node == null || !_passes(node!, filter)) selectedNode = shown.firstOrNull?.id;
    notifyListeners();
  }

  /// a node whose roles changed moves into the list of its new role - the filter follows it
  void _keepSelectionVisible() {
    final n = node;
    if (n == null || _passes(n, nodeFilter)) return;
    nodeFilter = n.roles.where(problemRoles.contains).firstOrNull ?? (isTransit(n) ? transitFilter : '');
  }

  void newProblem(String type) {
    final s = modules[type];
    if (s == null) return;
    edit(() {
      problemName = scenario.addProblem(type, strings(s.label), s.defaultParameters()).name;
      tab = DataTab.parameters;
    });
  }

  /// [keepTab]: chosen in the solution - the solution stays in view
  /// arrow keys: the previous (-1) or next (+1) entry of the list of the tab - nodes, edges, connections of the
  /// solution; without a selection the first or last one
  void moveSelection(int delta) {
    int? next(int? current, int length) => length == 0
        ? null
        : current == null
        ? (delta > 0 ? 0 : length - 1)
        : (current + delta).clamp(0, length - 1);
    switch (tab) {
      case DataTab.nodes:
        final list = filteredNodes;
        final i = list.indexWhere((n) => n.id == selectedNode);
        final k = next(i < 0 ? null : i, list.length);
        if (k != null) selectNode(list[k].id, keepTab: true);
      case DataTab.network:
        final k = next(selectedEdge, network?.edges.length ?? 0);
        if (k != null) selectEdge(k);
      case DataTab.solution:
        final k = next(selectedFlow, connections.length);
        if (k != null && k != selectedFlow) selectFlow(k);
      case DataTab.parameters:
        break;
    }
  }

  void selectNode(String? id, {bool keepTab = false}) {
    selectedNode = id;
    placing = false;
    _keepSelectionVisible(); // e.g. a node chosen on the map
    if (id != null && !keepTab && tab != DataTab.nodes) tab = DataTab.nodes;
    notifyListeners();
  }

  void setTab(DataTab t) {
    tab = t;
    notifyListeners();
  }

  void setPlacing(bool v) {
    placing = v;
    if (v) addingNodes = false;
    notifyListeners();
  }

  /// nodes by clicks into the map - one mode at a time: no edge drawn, no position set
  void setAddingNodes(bool v) {
    addingNodes = v;
    if (v) {
      placing = false;
      drawingEdge = false;
      edgeStart = null;
    }
    notifyListeners();
  }

  void addNode(LatLng position) {
    edit(() {
      // the role of the list shown, else the last role of the problem (tpp: customer) - none for a problem
      // without roles (tsp, shortest path) and for the transshipment nodes
      final role = nodeFilter == AppState.transitFilter
          ? 'transit'
          : nodeFilter != null && nodeFilter!.isNotEmpty
          ? nodeFilter!
          : spec != null
          ? problemRoles.lastOrNull
          : 'customer';
      selectedNode = scenario.addNode(position, roles: [?role]).id;
      tab = DataTab.nodes;
    });
  }

  void deleteNode() {
    final id = selectedNode;
    if (id == null) return;
    edit(() {
      final ids = scenario.nodes.map((n) => n.id).toList();
      final i = ids.indexOf(id);
      scenario.removeNode(id);
      final rest = scenario.nodes;
      selectedNode = rest.isEmpty ? null : rest[i.clamp(0, rest.length - 1)].id;
    });
  }

  void tapMap(LatLng p) {
    if (addingNodes) {
      addNode(p);
    } else if (placing && node != null) {
      edit(() {
        node!.position = p;
        placing = false;
      });
    } else {
      return;
    }
    clickedGeometry = geometry;
    final n = node;
    if (n != null && reverseGeocoding) addressOf(n.id, n.position); // as stored - rounded
  }

  /// tests without a core switch it off
  static bool reverseGeocoding = true;

  /// the address of a node set on the map, in the background - only into an empty address field; without an
  /// answer (offline, older core) the address stays empty
  Future<void> addressOf(String id, LatLng position) async {
    try {
      final hit = await (await _getBackend()).reverse(position);
      final n = scenario.node(id);
      if (hit == null || hit.address.isEmpty || n == null || (n.address ?? '').isNotEmpty) return;
      // moved again meanwhile - the coordinates are stored rounded, a click is more exact
      if (const Distance().as(LengthUnit.Meter, n.position, position) > 1) return;
      edit(() {
        n.address = hit.address;
        n.json['addressDetails'] = hit.addressDetails;
      });
    } catch (_) {}
  }

  //*********** computing ************

  Backend? _backend;
  Future<Backend>? _starting;
  Backend? _startingBackend;
  String? status; // waiting, running, starting ... while solving
  String? jobId;
  String? message; // last error or note for the status bar
  String? lastResult; // status of the last solving: solution, noSolution, error, cancelled
  Completer<ProblemAnswer?>? _cancelSolve;
  bool get solving => status != null;

  Future<Backend> _getBackend() {
    if (_backend != null) return Future.value(_backend!);
    return _starting ??= () async {
      final b = createBackend(_backendSettings);
      _startingBackend = b;
      try {
        await b.start();
      } catch (e) {
        if (identical(_startingBackend, b)) {
          _starting = null;
          _startingBackend = null;
        }
        rethrow;
      }
      if (!identical(_startingBackend, b)) {
        await b.close(); // reset while starting
        throw BackendException(499, 'the solver has been stopped');
      }
      _backend = b;
      _starting = null;
      _startingBackend = null;
      return b;
    }();
  }

  Future<void> _closeBackend() async {
    final b = _backend;
    _backend = null;
    await b?.close();
  }

  /// stops the solver (also one that is just starting) - the next request starts a new one; not while solving
  Future<void> resetBackend({bool force = false}) async {
    if (solving && !force) return;
    final starting = _startingBackend;
    _startingBackend = null;
    _starting = null;
    await _closeBackend();
    await starting?.close();
  }

  Future<void> solve() async {
    final p = problem;
    if (p == null || solving) return;
    final name = p.name;
    final rev = revision;
    // checks of the app - the core would refuse the problem
    final missing = [
      if (spec?.network == NetworkUse.required && network == null) strings('ui.net.required'),
      for (final e in spec?.validateParameters(p.parameters) ?? const <Message>[]) strings.message(e),
      ...nodeProblems,
    ];
    if (missing.isNotEmpty) {
      message = missing.join('\n');
      lastResult = 'error';
      notifyListeners();
      return;
    }
    // the data at the start - edits while solving do not reach the solver, they make the solution stale
    final data = jsonDecode(jsonEncode(scenario.json)) as Map<String, dynamic>;
    message = null;
    lastResult = null;
    status = 'starting';
    final cancelled = _cancelSolve = Completer<ProblemAnswer?>();
    notifyListeners();
    try {
      // a cancel before the problem has an id (solver starting, matrix of OSM) gives up waiting at once
      final b = await Future.any([_getBackend(), cancelled.future.then((_) => null)]);
      if (b == null) throw const _Cancelled();
      status = 'waiting';
      notifyListeners();
      final answer = await Future.any([
        b.solveScenario(
          data,
          name,
          onStatus: (a) {
            jobId = a.id;
            if (!finishedStatus.contains(a.status)) status = a.status;
            notifyListeners();
          },
        ),
        cancelled.future,
      ]);
      if (answer == null) throw const _Cancelled();
      lastResult = answer.status;
      if (answer.status == 'cancelled') return; // cancelled by the user - no error
      if (answer.solution != null) {
        solutions[name] = SolutionState(answer.solution!, rev);
        selectedFlow = null;
        selectedRoute = null;
        highlightedNode = null;
        if (problemName == name) tab = DataTab.solution;
      }
      message = answer.status == 'solution' ? null : '${strings('ui.status.${answer.status}')}: ${answer.message}';
    } on _Cancelled {
      lastResult = 'cancelled';
    } on BackendException catch (e) {
      if (cancelled.isCompleted) {
        lastResult = 'cancelled'; // the solver has been stopped by the cancel
      } else {
        lastResult = 'error'; // refused by the core, e.g. a node without a way in the network
        message = e.outdated ? strings('ui.error.outdated') : '${strings('ui.status.error')}: $e';
      }
    } catch (e) {
      lastResult = 'error';
      message = '${strings('ui.status.error')}: $e';
    } finally {
      status = null;
      jobId = null;
      _cancelSolve = null;
      notifyListeners();
    }
  }

  /// cancels the problem being solved: with an id the core cancels it (and stops the solver), before that the
  /// app gives up waiting and stops the local solver (it starts again with the next request)
  Future<void> cancel() async {
    final id = jobId;
    final b = _backend;
    if (id != null && b != null) {
      try {
        await b.cancel(id).timeout(requestTimeout);
        return;
      } catch (_) {
        // the solver does not answer - stopped below
      }
    }
    final c = _cancelSolve;
    if (c == null || c.isCompleted) return;
    c.complete(null);
    await resetBackend(force: true);
  }

  //*********** old LogisticsLab files ************

  /// extensions of the old files - converted by the core (convertX.py)
  static const oldFormats = ['tppx', 'tspx', 'clpx', 'dlpx', 'nwfx', 'vrpx'];

  /// formats of LogisticsLab 4 and older - planar coordinates and own matrices, not convertible
  static const legacyFormats = ['TPP', 'TSP', 'NWF', 'WLP', 'VRP', 'CLP', 'DLP', 'STP', 'LOP'];

  static bool isOldFile(String name) => oldFormats.contains(name.split('.').last.toLowerCase());

  /// converts an old file and opens the scenario - not saved yet (Save asks for the place)
  Future<void> importOld(String fileName, String content) async {
    final (json, name) = await convertOld(fileName, content);
    openImported(json, name);
  }

  /// scenario of an old file and its name - opened with openImported (not, if the import was cancelled)
  Future<(Map<String, dynamic>, String)> convertOld(String fileName, String content) async {
    final backend = await _getBackend();
    return backend.convert(fileName, content);
  }

  void openImported(Map<String, dynamic> json, String name) {
    openScenario(Scenario(json), name: name);
    dirty = true;
    notifyListeners();
  }

  //*********** geocoding ************

  /// places of the address - hits near the other nodes first
  Future<List<GeoHit>> geocode(String address, {String? exceptNode}) async {
    final others = [
      for (final n in scenario.nodes)
        if (n.id != exceptNode) n.position,
    ];
    final near = others.isEmpty
        ? null
        : LatLng(
            others.map((p) => p.latitude).reduce((a, b) => a + b) / others.length,
            others.map((p) => p.longitude).reduce((a, b) => a + b) / others.length,
          );
    final backend = await _getBackend();
    return backend.geocode(address, near: near);
  }

  //*********** course of the edges on the map ************

  final _routes = <String, List<LatLng>>{}; // loaded courses - kept for other files with the same coordinates
  final _routing = <String>{}; // queued or loading
  final _routeQueue = <(String, LatLng, LatLng, String)>[];
  final _routeFailures = <String, int>{}; // failed attempts of a course
  final _routeEnds = <String, (LatLng, LatLng, String)>{};
  bool _routeWorker = false;

  /// attempts and pauses before a course is given up - a server may not answer for a moment
  static const _routeRetries = [Duration(seconds: 2), Duration(seconds: 10), Duration(seconds: 30)];

  /// courses being loaded, courses given up (shown straight)
  int get routesLoading => _routing.length;
  int get routesMissing => _routeFailures.values.where((n) => n > _routeRetries.length).length;

  /// points of an edge - along the roads if the matrix source is OSM (loaded in the background), else straight
  List<LatLng> edgePoints(LatLng a, LatLng b) {
    if (!scenario.usesRoads) return [a, b];
    final mode = scenario.travelmode;
    final key = '$mode|${a.latitude},${a.longitude}|${b.latitude},${b.longitude}';
    final r = _routes[key];
    if (r != null) return r;
    if ((_routeFailures[key] ?? 0) == 0) _queueRoute(key, a, b, mode);
    return [a, b]; // until the course is loaded
  }

  void _queueRoute(String key, LatLng a, LatLng b, String mode) {
    if (!_routing.add(key)) return;
    _routeEnds[key] = (a, b, mode);
    _routeQueue.add((key, a, b, mode));
    _runRoutes();
  }

  /// courses given up are loaded again
  void retryRoutes() {
    final failed = [
      for (final MapEntry(:key, :value) in _routeFailures.entries)
        if (value > _routeRetries.length) key,
    ];
    for (final key in failed) {
      _routeFailures.remove(key);
      final (a, b, mode) = _routeEnds[key]!;
      _queueRoute(key, a, b, mode);
    }
    notifyListeners();
  }

  Future<void> _runRoutes() async {
    if (_routeWorker) return;
    _routeWorker = true;
    try {
      while (_routeQueue.isNotEmpty) {
        final (key, a, b, mode) = _routeQueue.removeAt(0);
        try {
          final backend = await _getBackend();
          final points = await backend.route([a, b], mode).timeout(requestTimeout);
          _routes[key] = points.length >= 2 ? points : [a, b];
          _routeFailures.remove(key);
          _routing.remove(key);
        } catch (_) {
          // not given up at once - the server may not answer or the solver restart
          final n = (_routeFailures[key] ?? 0) + 1;
          _routeFailures[key] = n;
          if (n <= _routeRetries.length) {
            Timer(_routeRetries[n - 1], () {
              _routing.remove(key);
              _queueRoute(key, a, b, mode);
            });
          } else {
            _routing.remove(key);
          }
        }
        notifyListeners();
      }
    } finally {
      _routeWorker = false;
    }
  }

  @override
  void dispose() {
    _closeBackend();
    super.dispose();
  }
}

/// the user has cancelled solving
class _Cancelled implements Exception {
  const _Cancelled();
}
