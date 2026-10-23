/// State of the app: the open scenario, the chosen problem and node, the solutions and the computing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend/backend.dart';
import 'i18n/strings.dart';
import 'model/scenario.dart';
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
    _routes.clear();
    notifyListeners();
  }

  //*********** scenario ************

  Scenario scenario = Scenario.empty();
  int opened = 0; // counts the opened scenarios
  int geometry = 0; // changes with the nodes or their coordinates - the map then shows all nodes
  String? fileName; // shown in the header
  String? filePath; // desktop: Save writes there
  bool dirty = false;
  int revision = 0; // changed with every edit - a solution of an older revision is stale

  String? problemName;
  String? selectedNode;
  DataTab tab = DataTab.nodes;
  bool placing = false; // next tap into the map sets the position of the selected node
  final solutions = <String, SolutionState>{};

  Problem? get problem => problemName == null ? null : scenario.problem(problemName!);
  ModuleSpec? get spec => modules[problem?.type];
  Node? get node => selectedNode == null ? null : scenario.node(selectedNode!);
  SolutionState? get solution => problemName == null ? null : solutions[problemName];

  /// roles of the nodes used by the problem - all roles without a problem (type)
  List<String> get problemRoles => spec?.problemRoles(problem?.parameters ?? const {}) ?? nodeRoles;

  /// active and with a role in the problem - other nodes are pale in the list and on the map
  bool isRelevant(Node n) => n.active && n.roles.any(problemRoles.contains);

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
    _routes.clear();
    final first = s.problems.where((p) => modules.containsKey(p.type)).firstOrNull ?? s.problems.firstOrNull;
    problemName = first?.name;
    selectedNode = s.nodes.firstOrNull?.id;
    nodeFilter = null;
    selectedEdge = null;
    drawingEdge = false;
    edgeStart = null;
    selectedFlow = null;
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
    selectedEdge = null;
    drawingEdge = false;
    if (nodeFilter != null && nodeFilter!.isNotEmpty && !problemRoles.contains(nodeFilter)) nodeFilter = null;
    _keepSelectionVisible();
    notifyListeners();
  }

  //*********** solution ************

  int? selectedFlow; // index in the connections (assignments) of the solution - highlighted on the map

  void selectFlow(int? i) {
    selectedFlow = i == selectedFlow ? null : i; // a second tap removes the highlight
    if (selectedFlow != null) selectedEdge = null; // only one highlight on the map
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
  bool addEdge(String from, String to) {
    final net = network;
    if (net == null || from == to || net.hasEdge(from, to)) return false;
    edit(() {
      net.addEdge(from, to);
      selectedEdge = net.edges.length - 1;
      tab = DataTab.network;
    });
    return true;
  }

  /// the missing edges from every node of the first role of the problem to every node of the second
  /// (tpp: suppliers -> customers) - returns the number of new edges
  int addAllEdges() {
    final net = network;
    final roles = spec?.roles ?? const <RoleSpec>[];
    if (net == null || roles.length < 2) return 0;
    final params = problem!.parameters;
    final from = [
      for (final n in scenario.nodes)
        if (n.roles.contains(spec!.nodeRole(roles[0], params))) n.id,
    ];
    final to = [
      for (final n in scenario.nodes)
        if (n.roles.contains(spec!.nodeRole(roles[1], params))) n.id,
    ];
    var count = 0;
    edit(() {
      for (final a in from) {
        for (final b in to) {
          if (a != b && !net.hasEdge(a, b)) {
            net.addEdge(a, b);
            count++;
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

  void selectEdge(int? i) {
    selectedEdge = i;
    if (i != null) selectedFlow = null; // only one highlight on the map
    notifyListeners();
  }

  void setDrawingEdge(bool v) {
    drawingEdge = v && network != null;
    edgeStart = null;
    placing = false;
    notifyListeners();
  }

  /// a node tapped on the map: selection, or an end of the edge being drawn
  void tapNode(String id) {
    if (!drawingEdge) return selectNode(id);
    if (edgeStart == null) {
      edgeStart = id;
      notifyListeners();
      return;
    }
    final start = edgeStart!;
    drawingEdge = false;
    edgeStart = null;
    if (!addEdge(start, id)) notifyListeners();
  }

  //*********** filter of the node list ************

  /// null: all nodes, '': nodes without a role in the problem, else a role of the problem
  String? nodeFilter;

  bool _passes(Node n, String? filter) => filter == null
      ? true
      : filter.isEmpty
      ? !n.roles.any(problemRoles.contains)
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
    nodeFilter = n.roles.where(problemRoles.contains).firstOrNull ?? '';
  }

  void newProblem(String type) {
    final s = modules[type];
    if (s == null) return;
    edit(() {
      problemName = scenario.addProblem(type, strings(s.label), s.defaultParameters()).name;
      tab = DataTab.parameters;
    });
  }

  void selectNode(String? id) {
    selectedNode = id;
    placing = false;
    _keepSelectionVisible(); // e.g. a node chosen on the map
    if (id != null && tab != DataTab.nodes) tab = DataTab.nodes;
    notifyListeners();
  }

  void setTab(DataTab t) {
    tab = t;
    notifyListeners();
  }

  void setPlacing(bool v) {
    placing = v;
    notifyListeners();
  }

  void addNode(LatLng position) {
    edit(() {
      // the role of the list shown, else the last role of the problem (tpp: customer)
      final role = nodeFilter != null && nodeFilter!.isNotEmpty
          ? nodeFilter!
          : problemRoles.length < nodeRoles.length
          ? problemRoles.last
          : 'customer';
      selectedNode = scenario.addNode(position, roles: [role]).id;
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
    if (!placing || node == null) return;
    edit(() {
      node!.position = p;
      placing = false;
    });
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
          scenario.json,
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
        if (problemName == name) tab = DataTab.solution;
      }
      message = answer.status == 'solution' ? null : '${strings('ui.status.${answer.status}')}: ${answer.message}';
    } on _Cancelled {
      lastResult = 'cancelled';
    } on BackendException catch (e) {
      if (cancelled.isCompleted) {
        lastResult = 'cancelled'; // the solver has been stopped by the cancel
      } else {
        message = e.outdated ? strings('ui.error.outdated') : '${strings('ui.status.error')}: $e';
      }
    } catch (e) {
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

  final _routes = <String, List<LatLng>>{};
  final _routing = <String>{};
  final _routeQueue = <(String, LatLng, LatLng)>[];
  bool _routeWorker = false;

  /// points of an edge - along the roads if the matrix source is OSM (loaded in the background), else straight
  List<LatLng> edgePoints(LatLng a, LatLng b) {
    if (!scenario.usesRoads) return [a, b];
    final key = '${scenario.travelmode}|${a.latitude},${a.longitude}|${b.latitude},${b.longitude}';
    final r = _routes[key];
    if (r != null) return r;
    if (_routing.add(key)) {
      _routeQueue.add((key, a, b));
      _runRoutes();
    }
    return [a, b];
  }

  Future<void> _runRoutes() async {
    if (_routeWorker) return;
    _routeWorker = true;
    try {
      while (_routeQueue.isNotEmpty) {
        final (key, a, b) = _routeQueue.removeAt(0);
        try {
          final backend = await _getBackend();
          final points = await backend.route([a, b], scenario.travelmode);
          _routes[key] = points.length >= 2 ? points : [a, b];
        } catch (_) {
          _routes[key] = [a, b]; // shown straight - the computing is not available
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
