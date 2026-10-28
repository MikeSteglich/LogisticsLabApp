/// The solution of a problem as Excel file - the tables of the solution tab with numbers instead of formatted texts.
///
///   overview      problem, status, results (the objective marked), parameters, warnings
///   locations     locations and assignments (location problems)
///   tours         overview of the tours, their sections and the rides (routing); sections of a tour (tsp, cpp, ...)
///   connections   flows with rates and costs and the nodes with their quantities (transport problems, network flows)
///
/// Names instead of ids, headers in the language of the app, units in the headers.
library;

import 'dart:typed_data';

import '../app_state.dart';
import '../modules/modules.dart';
import 'core_texts.dart';
import 'scenario.dart';
import 'solution_analysis.dart';
import 'xlsx.dart';

Uint8List solutionXlsx(AppState s) => encodeXlsx(solutionSheets(s));

List<XlsxSheet> solutionSheets(AppState s) {
  final sol = s.solution;
  final spec = s.spec;
  if (sol == null || spec == null) return const [];
  return [
    _overview(s, spec),
    if (sol.results != null) ...[
      if (spec.group == ModuleGroup.location && sol.results!['nodes'] != null)
        ..._locations(s)
      else if (s.isRoute)
        ..._routes(s)
      else
        ..._flows(s),
    ],
  ];
}

/// unit of the values of the solution: €, km, min, ...
String _valueUnit(AppState s) {
  final u = s.solution?.document['valueUnit'] as String?;
  return u == null || u == 'costs' ? '€' : u;
}

String _timeUnit(AppState s) => s.scenario.units['time'] as String? ?? 'min';

String _with(String label, String unit) => '$label ($unit)';

String _name(AppState s, Object? id) => s.nameOf('$id');

num? _percent(Object? v) => v is num ? v * 100 : null;

//*********** overview ************

XlsxSheet _overview(AppState s, ModuleSpec spec) {
  final t = s.strings;
  final sol = s.solution!;
  final doc = sol.document;
  final res = sol.results;
  final params = s.solutionParameters;
  final sheet = XlsxSheet(t('ui.export.overview'));
  sheet.add([t('ui.export.problem'), s.problemName], bold: true);
  sheet.add([t('ui.export.type'), t(spec.label)]);
  sheet.add([t('ui.sol.status'), t('ui.status.${sol.status}')]);
  if (doc['message'] case final String m when m.isNotEmpty && sol.status != 'solution') {
    sheet.add([t('ui.export.message'), coreMessage(t, m)]);
  }
  if (doc['created'] case final String c) sheet.add([t('ui.export.created'), c]);
  if (res?['solvingTime'] case final num v) sheet.add([_with(t('ui.export.solvingTime'), 's'), v]);
  if ((doc['matrixInfo'] as Map?)?['source'] case final String m) {
    sheet.add([t('field.matrixSource'), t.has('choice.matrixSource.$m') ? t('choice.matrixSource.$m') : m]);
  }

  // the results as the cards of the solution tab - the objective marked
  if (res != null) {
    final summary = (res['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final objectiveKey = spec.objective?.call(params);
    final weighted = s.objectiveWeighted;
    sheet.empty();
    sheet.add([t('ui.export.results'), t('ui.export.value'), t('ui.export.unit')], bold: true);
    for (final col in spec.summary) {
      final v = col.key == 'objVal' ? res['objVal'] : summary[col.key];
      if (v is! num) continue;
      // the same value as another column: left out as in the solution tab
      if (col.hideIfSameAs case final other?) {
        final o = other == 'objVal' ? res['objVal'] : summary[other];
        if (o is num && (v - o).abs() <= 1e-6 * (o.abs() > 1 ? o.abs() : 1)) continue;
      }
      final isWeighted = weighted && col.weightedLabelKey != null;
      final label = t(isWeighted ? col.weightedLabelKey! : col.label);
      final (value, unit) = isWeighted
          ? (v, '')
          : switch (col.unit) {
              '€' => (v, _valueUnit(s)),
              'EUR' => (v, '€'),
              '@time' => (v, _timeUnit(s)),
              '%' => (v * 100, '%'),
              final u => (v, u ?? ''),
            };
      sheet.add([
        col.key == objectiveKey ? '$label (${t('ui.export.objective')})' : label,
        value,
        unit,
      ], bold: col.key == objectiveKey);
    }
  }

  // the parameters of the solution - with their labels and the texts of their choices
  final fields = {for (final f in spec.parameters) f.key: f};
  final shown = [
    for (final MapEntry(:key, :value) in params.entries)
      if (value != null && value != '' && value is! Map && value is! List) (key, value),
  ];
  if (shown.isNotEmpty) {
    sheet.empty();
    sheet.add([t('ui.export.parameters')], bold: true);
    for (final (key, value) in shown) {
      final f = fields[key];
      final label = f != null && t.has(f.label) ? t(f.label) : key;
      final text = switch (value) {
        bool b => t(b ? 'ui.export.yes' : 'ui.export.no'),
        String v when f?.kind == FieldKind.choice && t.has('choice.$key.$v') => t('choice.$key.$v'),
        String v when f?.kind == FieldKind.node => _name(s, v),
        _ => value,
      };
      sheet.add([label, text]);
    }
  }

  final warnings = coreWarnings(t, doc);
  if (warnings.isNotEmpty) {
    sheet.empty();
    sheet.add([t('ui.export.warnings')], bold: true);
    for (final w in warnings) {
      sheet.add([w]);
    }
  }
  return sheet;
}

//*********** location problems ************

List<XlsxSheet> _locations(AppState s) {
  final t = s.strings;
  final res = s.solution!.results!;
  final nodes = (res['nodes'] as Map).cast<String, dynamic>();
  int open(String id) => (nodes[id]['open'] as int?) ?? 1;
  final ids = nodes.keys.toList()..sort((a, b) => open(b).compareTo(open(a)));
  final found = s.foundLocations;
  final withCapacity = nodes.values.any((n) => n['capacity'] != null);
  final withFixed = nodes.values.any((n) => n['fixedCost'] != null);
  final locations = XlsxSheet(t('ui.sol.locations'));
  locations.add([
    t('ui.sol.location'),
    t('ui.sol.status'),
    t('ui.sol.customers'),
    t('ui.sol.amount'),
    if (withCapacity) ...[t('field.capacity'), _with(t('ui.sol.utilization'), '%')],
    if (withFixed) _with(t('field.openingCost'), '€'),
    if (found.isNotEmpty) ...[t('ui.export.latitude'), t('ui.export.longitude')],
  ], bold: true);
  for (final id in ids) {
    final n = (nodes[id] as Map).cast<String, dynamic>();
    final isOpen = open(id) == 1;
    locations.add([
      _name(s, id),
      t(isOpen ? 'ui.sol.isOpen' : 'ui.sol.isClosed'),
      isOpen ? n['nrOfAssigned'] ?? 0 : null,
      isOpen ? n['load'] ?? 0 : null,
      if (withCapacity) ...[n['capacity'], _percent(n['utilization'])],
      if (withFixed) n['fixedCost'],
      if (found.isNotEmpty) ...[found[id]?.latitude, found[id]?.longitude],
    ]);
  }

  // the assignments - with their value and their part of the objective
  final assignments = s.connections;
  final withCosts = assignments.any((a) => a['costs'] != null);
  final withShares = assignments.any((a) => a['share'] != null);
  final weighted = s.objectiveWeighted;
  final isCosts = s.solution!.document['valueUnit'] == 'costs' || s.problem?.type == 'wlp';
  final valueLabel = t(switch (s.solution!.document['valueUnit']) {
    'costs' => 'result.rate',
    final u when u == s.scenario.units['time'] => 'ui.sol.travelTime',
    _ => 'ui.sol.value',
  });
  final sheet = XlsxSheet(t('ui.sol.assignments'));
  sheet.add([
    t('ui.sol.location'),
    t('role.customer'),
    t('ui.sol.amount'),
    if (withShares) _with(t('ui.sol.share'), '%'),
    _with(valueLabel, _valueUnit(s)),
    if (withCosts) weighted ? t('ui.sol.rating') : _with(t(isCosts ? 'ui.sol.costs' : 'ui.sol.rating'), _valueUnit(s)),
  ], bold: true);
  for (final a in assignments) {
    sheet.add([
      _name(s, a['from']),
      _name(s, a['to']),
      a['flow'] ?? 0,
      if (withShares) _percent(a['share']),
      a['value'],
      if (withCosts) a['costs'],
    ]);
  }
  return [locations, sheet];
}

//*********** tours ************

List<XlsxSheet> _routes(AppState s) {
  final t = s.strings;
  final clock = s.clock;
  final res = s.solution!.results!;
  final routes = ((res['routes'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final names = s.routeNames;
  final legs = s.connections;
  final unit = _valueUnit(s);
  final time = _timeUnit(s);
  final vrp = routes.isNotEmpty && routes.first['capacity'] != null;
  String tourName(int i) => i < names.length ? names[i] : '${i + 1}';
  final sheets = <XlsxSheet>[];

  // vehicle routing: a row per tour
  if (vrp) {
    final withTimes = routes.any((r) => r['duration'] is num);
    final overview = XlsxSheet(t('ui.export.tours'));
    overview.add([
      t('ui.sol.tourVehicle'),
      t('ui.sol.stops'),
      t('ui.sol.amount'),
      _with(t('ui.sol.utilization'), '%'),
      _with(t('ui.sol.distance'), unit),
      if (withTimes) ...[_with(t('ui.sol.totalTime'), time), t('ui.sol.departure'), t('ui.export.return')],
    ], bold: true);
    for (final (i, r) in routes.indexed) {
      overview.add([
        tourName(i),
        r['stops'],
        r['load'] ?? 0,
        _percent(r['utilization']),
        r['distance'] ?? 0,
        if (withTimes) ...[r['duration'], clock.format(r['start'] as num?), clock.format(r['end'] as num?)],
      ]);
    }
    sheets.add(overview);
  }

  // the sections - with their tour, the schedule if the tours have times
  final schedule = legs.any((a) => a['departure'] != null);
  final withAmounts = legs.any((a) => a['amount'] != null);
  final withLoad = legs.any((a) => a['load'] != null);
  final withWaiting = legs.any((a) => (a['waiting'] as num? ?? 0) > 0.5);
  final withPasses = legs.any((a) => a['passes'] != null);
  String window(Object? id) {
    final n = s.scenario.node('$id');
    if (n == null) return '';
    return s.nodeData(n).where((e) => e.$1.kind == FieldKind.timeWindow).map((e) => e.$2).firstOrNull ?? '';
  }

  final withWindows = schedule && legs.any((a) => window(a['to']).isNotEmpty);
  final sheet = XlsxSheet(t('ui.export.legs'));
  sheet.add([
    if (vrp) t('ui.sol.tourVehicle'),
    t('ui.sol.leg'),
    t('ui.sol.from'),
    t('ui.sol.to'),
    if (schedule) ...[
      t('ui.sol.departure'),
      _with(t('ui.sol.travelTime'), time),
      _with(t('ui.sol.waiting'), time),
      t('ui.sol.arrival'),
      if (withWindows) t('ui.col.timeWindow'),
      _with(t('ui.sol.service'), time),
    ] else if (withWaiting)
      _with(t('ui.sol.waiting'), time),
    if (withAmounts || schedule) t('ui.sol.amount'),
    if (withLoad) t('ui.sol.load'),
    _with(t(schedule ? 'ui.sol.distance' : 'ui.sol.legValue'), unit),
    if (!schedule) _with(t('ui.sol.cumulated'), unit),
    if (withPasses) t('ui.sol.passes'),
  ], bold: true);
  final cumulated = <Object?, num>{};
  for (final a in legs) {
    final v = a['value'];
    if (v is! num) continue;
    final route = a['route'];
    cumulated[route] = (cumulated[route] ?? 0) + v;
    final ready = a['arrival'] is num ? (a['arrival'] as num) + (a['waiting'] as num? ?? 0) : null;
    sheet.add([
      if (vrp) route is int ? tourName(route) : null,
      a['leg'],
      _name(s, a['from']),
      [_name(s, a['to']), s.via(a)].where((x) => x.isNotEmpty).join(' '),
      if (schedule) ...[
        clock.format(a['departure'] as num?),
        a['travel'],
        a['waiting'],
        clock.format(ready),
        if (withWindows) window(a['to']),
        a['service'],
      ] else if (withWaiting)
        a['waiting'],
      if (withAmounts || schedule) a['amount'],
      if (withLoad) a['load'],
      v,
      if (!schedule) cumulated[route],
      if (withPasses) a['passes'] == null ? null : '${a['pass']}/${a['passes']}',
    ]);
  }
  sheets.add(sheet);

  // pickup and delivery: the rides
  final requests = ((res['requests'] as List?) ?? const []).cast<Map<String, dynamic>>();
  if (requests.isNotEmpty) {
    String tour(Object? vehicle) {
      final i = routes.indexWhere((r) => r['vehicle'] == vehicle);
      return i < 0 ? '${vehicle ?? ''}' : tourName(i);
    }

    final rides = XlsxSheet(t('ui.sol.rides'));
    rides.add([
      t('role.pickup'),
      t('role.delivery'),
      t('ui.sol.tourVehicle'),
      t('ui.sol.amount'),
      _with(t('ui.sol.direct'), time),
      _with(t('ui.sol.ride'), time),
      _with(t('ui.sol.detour'), '×'),
    ], bold: true);
    for (final q in requests) {
      rides.add([
        _name(s, q['pickup']),
        _name(s, q['delivery']),
        tour(q['vehicle']),
        q['amount'] ?? 0,
        q['direct'],
        q['ride'],
        q['detour'],
      ]);
    }
    sheets.add(rides);
  }
  return sheets;
}

//*********** transport problems and network flows ************

List<XlsxSheet> _flows(AppState s) {
  final t = s.strings;
  // all connections - also if the solution tab shows one commodity or mode
  final connections = SolutionAnalysis.connectionsOf(s.solution!.results, null);
  final withRates = connections.any((a) => a['rate'] != null || a['rates'] != null);
  // several commodities or modes: a column per commodity or mode - its quantity and its cost rate
  final splitKey = connections.any((a) => a['flows'] != null) ? 'flows' : 'modes';
  final records = splitKey == 'flows' ? s.scenario.commodities : s.scenario.modes;
  final parts = [
    for (final r in records)
      if (connections.any((a) => (a[splitKey] as Map?)?.containsKey(r['id']) ?? false)) r,
  ];
  final withUtilization = connections.any((a) => a['utilization'] != null);
  final (rateLabel, costLabel) = s.rateLabels;
  final sheet = XlsxSheet(t('ui.export.connections'));
  sheet.add([
    t('ui.sol.from'),
    t('ui.sol.to'),
    for (final r in parts) Scenario.recordName(r),
    t('result.flow'),
    if (withRates) ...[
      if (parts.isEmpty) _with(rateLabel, '€'),
      for (final r in parts) _with('${Scenario.recordName(r)}: $rateLabel', '€'),
      _with(costLabel, '€'),
    ],
    if (withUtilization) _with(t('ui.sol.utilization'), '%'),
  ], bold: true);
  for (final a in connections) {
    final flow = a['flow'] as num? ?? 0;
    sheet.add([
      _name(s, a['from']),
      _name(s, a['to']),
      for (final r in parts) (a[splitKey] as Map?)?[r['id']] as num?,
      flow,
      if (withRates) ...[
        if (parts.isEmpty) a['rate'],
        for (final r in parts) (a['rates'] as Map?)?[r['id']] as num?,
        a['costs'] ?? (a['rate'] is num ? flow * (a['rate'] as num) : null),
      ],
      if (withUtilization) _percent(a['utilization']),
    ]);
  }
  final sheets = [sheet];

  // warehouses of a multi-stage WLP
  final open = s.openNodes;
  if (open.isNotEmpty) {
    final warehouses = XlsxSheet(t('ui.sol.open'));
    warehouses.add([t('ui.sol.location'), t('ui.sol.status')], bold: true);
    for (final MapEntry(:key, :value) in open.entries) {
      warehouses.add([_name(s, key), t(value ? 'ui.sol.isOpen' : 'ui.sol.isClosed')]);
    }
    sheets.add(warehouses);
  }

  // the nodes: target, actual quantity, share and partners
  if (s.analysis case final a?) {
    final nodes = XlsxSheet(t('ui.tab.nodes'));
    final withCapacity = a.uses.any((u) => u.capacity != null);
    nodes.add([
      t('ui.col.name'),
      t('ui.col.roles'),
      t('ui.sol.target'),
      t('ui.sol.actual'),
      _with(t('ui.sol.share'), '%'),
      if (withCapacity) ...[t('field.capacity'), _with(t('ui.sol.utilization'), '%')],
      t('ui.sol.partners'),
    ], bold: true);
    for (final u in a.uses) {
      nodes.add([
        u.node.name,
        t('role.${u.role}'),
        u.target,
        u.actual,
        _percent(u.share),
        if (withCapacity) ...[u.capacity, _percent(u.utilization)],
        u.partners.map((p) => '${_name(s, p.$1)} ${t.number(p.$2)}').join(', '),
      ]);
    }
    sheets.add(nodes);
  }
  return sheets;
}
