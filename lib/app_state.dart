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
    final args = _prefs.getString('backend.arguments');
    return BackendSettings(
      remote: !localBackendSupported || (_prefs.getBool('backend.remote') ?? d.remote),
      executable: _prefs.getString('backend.executable') ?? d.executable,
      arguments: args == null ? d.arguments : (jsonDecode(args) as List).cast<String>(),
      workingDirectory: _prefs.getString('backend.workingDirectory') ?? d.workingDirectory,
      url: _prefs.getString('backend.url') ?? d.url,
      apiKey: _prefs.getString('backend.apiKey') ?? d.apiKey,
    );
  }

  Future<void> setBackendSettings(BackendSettings s) async {
    _backendSettings = s;
    await _prefs.setBool('backend.remote', s.remote);
    await _prefs.setString('backend.executable', s.executable);
    await _prefs.setString('backend.arguments', jsonEncode(s.arguments));
    await _prefs.setString('backend.workingDirectory', s.workingDirectory);
    await _prefs.setString('backend.url', s.url);
    await _prefs.setString('backend.apiKey', s.apiKey);
    await _closeBackend();
    _routes.clear();
    notifyListeners();
  }

  //*********** scenario ************

  Scenario scenario = Scenario.empty();
  int opened = 0; // counts the opened scenarios - the map shows all nodes of a new one
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
  bool get solutionIsStale => solution != null && solution!.revision != revision;

  void openScenario(Scenario s, {String? name, String? path}) {
    scenario = s;
    opened++;
    fileName = name;
    filePath = path;
    dirty = false;
    revision++;
    solutions.clear();
    _routes.clear();
    final first = s.problems.where((p) => modules.containsKey(p.type)).firstOrNull ?? s.problems.firstOrNull;
    problemName = first?.name;
    selectedNode = s.nodes.firstOrNull?.id;
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
    change();
    dirty = true;
    revision++;
    notifyListeners();
  }

  void chooseProblem(String name) {
    problemName = name;
    notifyListeners();
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
      final roles = spec?.roles.map((r) => r.defaultRole).toList() ?? const <String>[];
      selectedNode = scenario.addNode(position, roles: roles.isEmpty ? const ['customer'] : [roles.last]).id;
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
  String? status; // waiting, running, starting ... while solving
  String? jobId;
  String? message; // last error or note for the status bar
  bool get solving => status != null;

  Future<Backend> _getBackend() {
    if (_backend != null) return Future.value(_backend!);
    return _starting ??= () async {
      final b = createBackend(_backendSettings);
      try {
        await b.start();
      } catch (e) {
        _starting = null;
        rethrow;
      }
      _backend = b;
      _starting = null;
      return b;
    }();
  }

  Future<void> _closeBackend() async {
    final b = _backend;
    _backend = null;
    await b?.close();
  }

  Future<void> solve() async {
    final p = problem;
    if (p == null || solving) return;
    final name = p.name;
    final rev = revision;
    message = null;
    status = 'starting';
    notifyListeners();
    try {
      final b = await _getBackend();
      status = 'waiting';
      notifyListeners();
      final answer = await b.solveScenario(
        scenario.json,
        name,
        onStatus: (a) {
          jobId = a.id;
          if (!finishedStatus.contains(a.status)) status = a.status;
          notifyListeners();
        },
      );
      if (answer.solution != null) {
        solutions[name] = SolutionState(answer.solution!, rev);
        if (problemName == name) tab = DataTab.solution;
      }
      message = answer.status == 'solution' ? null : '${strings('ui.status.${answer.status}')}: ${answer.message}';
    } catch (e) {
      message = '${strings('ui.status.error')}: $e';
    } finally {
      status = null;
      jobId = null;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    final id = jobId;
    if (id == null || _backend == null) return;
    try {
      await _backend!.cancel(id);
    } catch (e) {
      message = '$e';
      notifyListeners();
    }
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
