/// Nodes, edges and the solution as tables of the clipboard - copied to Excel and pasted from it.
///
///   copy    the nodes of the list (or the edges of the network) with the columns of the problem: name, id, latitude,
///           longitude, address, roles, active and the fields of the roles - numbers in the format of the language
///   paste   the same columns - recognised by their headers in the language of the app, in English or by their keys;
///           new nodes or edges, or the existing ones updated (by id, else by name)
///
/// A paste is checked first (TableImport.check) - the rows with errors are left out, the rest is applied at once.
/// Nodes with an address and without coordinates get the coordinates of the address (geocoding of the core).
library;

import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../modules/modules.dart';
import 'scenario.dart';
import 'solution_export.dart';
import 'table_text.dart';

enum TableKind { nodes, edges }

enum ImportMode { add, update }

/// a column of the table: a property of the node or edge, or a field of the problem
class TableColumn {
  final String key; // name, id, latitude, longitude, address, roles, active - from, to, directed - or a field key
  final String label; // message key of the header
  final FieldSpec? field;
  const TableColumn(this.key, this.label, [this.field]);
}

const _nodeBase = [
  TableColumn('name', 'ui.col.name'),
  TableColumn('id', 'ui.col.id'),
  TableColumn('latitude', 'ui.export.latitude'),
  TableColumn('longitude', 'ui.export.longitude'),
  TableColumn('address', 'ui.node.address'),
  TableColumn('roles', 'ui.col.roles'),
  TableColumn('active', 'ui.import.active'),
];

const _edgeBase = [
  TableColumn('from', 'ui.sol.from'),
  TableColumn('to', 'ui.sol.to'),
  TableColumn('directed', 'ui.import.directed'),
];

// further headers recognised for the base columns - English, German and short forms
const _aliases = {
  'name': ['name', 'bezeichnung', 'knoten', 'node', 'ort'],
  'id': ['id', 'nr', 'kennung'],
  'latitude': ['latitude', 'lat', 'breite', 'breitengrad', 'y'],
  'longitude': ['longitude', 'lon', 'lng', 'long', 'lange', 'langengrad', 'x'],
  'address': ['address', 'adresse', 'anschrift'],
  'roles': ['roles', 'role', 'rollen', 'rolle'],
  'active': ['active', 'aktiv'],
  'from': ['from', 'von', 'start', 'source'],
  'to': ['to', 'nach', 'ziel', 'target'],
  'directed': ['directed', 'gerichtet'],
  // the capacity of a node of a network flow (throughput)
  'maxCap': ['kapazitat', 'capacity', 'maxcap', 'durchsatz', 'maxdurchsatz', 'hochstdurchsatz'],
  'minCap': ['mincap', 'mindestdurchsatz'],
  // usual headers of fields
  'demand': ['bedarf', 'demand', 'menge', 'nachfrage'],
  'supply': ['supply', 'angebot', 'kapazitat'],
  'timeWindow': ['zeitfenster', 'timewindow'],
};

/// the columns of the problem - the base columns and the fields of its roles (nodes) or edges
List<TableColumn> tableColumns(AppState s, TableKind kind) {
  final spec = s.spec;
  final params = s.problem?.parameters ?? const <String, dynamic>{};
  final seen = <String>{};
  // also the fields the problem uses only with a parameter (fixed costs) - the values are kept as in the masks
  bool usable(FieldSpec f) =>
      !f.computed && f.kind != FieldKind.commodities && f.kind != FieldKind.modes && seen.add(f.key);
  if (kind == TableKind.edges) {
    // the edge fields of every problem of the network (e.g. a transportation problem over a min cost flow network)
    final net = s.problem?.network;
    return [
      ..._edgeBase,
      for (final f in [
        ...?spec?.edgeFields,
        for (final q in s.scenario.problems)
          if (net != null && q.network == net) ...?modules[q.type]?.edgeFields,
      ])
        if (usable(f)) TableColumn(f.key, f.label, f),
    ];
  }
  return [
    ..._nodeBase,
    if (spec != null)
      for (final r in spec.activeRoles(params))
        for (final f in r.nodeFields)
          if (usable(f)) TableColumn(f.key, f.label, f),
    for (final f in spec?.nodeFields ?? const <FieldSpec>[])
      if (usable(f)) TableColumn(f.key, f.label, f),
  ];
}

//*************** copy ************************************************

/// the nodes of the list or the edges of the network as table text - only columns with a value
String copyTable(AppState s, TableKind kind) {
  final t = s.strings;
  final columns = tableColumns(s, kind);
  final records = kind == TableKind.nodes
      ? [for (final n in s.filteredNodes) n.json]
      : [for (final e in s.network?.edges ?? const <Edge>[]) e.json];
  final rows = [
    for (final r in records) [for (final c in columns) _cellText(s, kind, c, r)],
  ];
  // the base columns of the kind always, a field only if a record has a value
  final keep = [
    for (final (i, c) in columns.indexed)
      if (c.field == null && c.key != 'address' || rows.any((r) => r[i].isNotEmpty)) i,
  ];
  return tableText([
    [for (final i in keep) t(columns[i].label)],
    for (final r in rows) [for (final i in keep) r[i]],
  ]);
}

String _number(AppState s, num v) => s.strings.number(v, decimals: 6, grouping: false);

String _yesNo(AppState s, bool v) => s.strings(v ? 'ui.export.yes' : 'ui.export.no');

String _cellText(AppState s, TableKind kind, TableColumn c, Map<String, dynamic> json) {
  final t = s.strings;
  if (kind == TableKind.nodes) {
    final n = Node(json);
    switch (c.key) {
      case 'name':
        return n.name;
      case 'id':
        return n.id;
      case 'latitude':
        return _number(s, n.position.latitude);
      case 'longitude':
        return _number(s, n.position.longitude);
      case 'address':
        return n.address ?? '';
      case 'roles':
        return n.roles.map((r) => t('role.$r')).join(', ');
      case 'active':
        return _yesNo(s, n.active);
    }
  } else {
    final e = Edge(json);
    switch (c.key) {
      case 'from':
        return s.nameOf(e.from);
      case 'to':
        return s.nameOf(e.to);
      case 'directed':
        return _yesNo(s, e.directedIn(s.network!));
    }
  }
  final f = c.field!;
  final v = json[f.key];
  if (v == null) return '';
  return switch (f.kind) {
    FieldKind.timeWindow when v is List =>
      '${s.clock.format(v[0] as num?)}–${s.clock.format(v.length > 1 ? v[1] as num? : null)}',
    FieldKind.boolean => _yesNo(s, v == true),
    FieldKind.choice => t.has('choice.${f.key}.$v') ? t('choice.${f.key}.$v') : '$v',
    FieldKind.node => s.nameOf('$v'),
    FieldKind.unlimited when v == 'M' => '',
    _ => v is num ? _number(s, v) : '$v',
  };
}

/// the solution as table text - the sheets of the Excel export one below the other, each with its title
String copySolution(AppState s) {
  final t = s.strings;
  final out = <List<String>>[];
  for (final sheet in solutionSheets(s)) {
    if (sheet.rows.isEmpty) continue;
    if (out.isNotEmpty) out.add(const []);
    out.add([sheet.name]);
    for (final r in sheet.rows) {
      out.add([for (final v in r) v is num ? t.number(v, decimals: 6, grouping: false) : '${v ?? ''}']);
    }
  }
  return tableText(out);
}

// headers of the parts of an address - in a table without a column of the address they make it up
const _streetParts = ['strasse', 'str', 'street', 'hausnummer', 'hausnr', 'housenumber', 'number', 'anschrift'];
const _placeParts = ['ort', 'stadt', 'city', 'town', 'gemeinde', 'place', 'wohnort', 'ortsteil'];
const _otherParts = [
  'plz',
  'postleitzahl',
  'postcode',
  'postalcode',
  'zip',
  'zipcode',
  'land',
  'country',
  'staat',
  'bundesland',
  'state',
  'region',
  'kreis',
  'landkreis',
  'district',
];

//*************** paste ************************************************

class ImportError {
  final int row; // row of the table, from 1 - as in Excel
  final String key; // message key
  final Map<String, Object> args;
  const ImportError(this.row, this.key, [this.args = const {}]);
}

class ImportCheck {
  int added = 0, updated = 0;
  final List<ImportError> errors = [];
  final List<(int, String)> toLocate = []; // (row, address) of the nodes whose coordinates are looked up
  final List<void Function(Scenario, Network?, Map<int, LatLng>)> _changes = [];
  bool get isEmpty => added + updated == 0;
}

class TableImport {
  final AppState state;
  final TableKind kind;
  final List<List<String>> rows;
  final List<TableColumn> columns;
  bool header;
  late List<String?> mapping; // column key of every column of the table - null: ignored
  ImportMode mode = ImportMode.add;
  String? role; // nodes without a column of the roles: this role
  List<int> addressParts = []; // without a column of the address: the columns it is made of (joined by commas)

  TableImport(this.state, this.kind, String text)
    : rows = parseTable(text),
      columns = tableColumns(state, kind),
      header = false {
    mapping = List.filled(width, null);
    // a header if the first row names known columns
    final guess = rows.isEmpty ? <String?>[] : [for (final c in rows.first) _columnOf(c)];
    header = guess.whereType<String>().length >= (width < 2 ? 1 : 2) || guess.contains('name');
    if (header) {
      final used = <String>{};
      mapping = [for (final k in guess) k != null && used.add(k) ? k : null];
    } else {
      _guessByValues();
    }
    final problemRoles = state.problemRoles;
    role = problemRoles.isEmpty ? 'customer' : problemRoles.last;
    // the role of a row from its values: supply, demand, ... - with a column of a main value of a role
    if (canDetectRoles) role = autoRole;
    // update if the names or ids exist already
    if (kind == TableKind.nodes) {
      final names = {for (final n in state.scenario.nodes) normalize(n.name)};
      final nameColumn = mapping.indexOf('name');
      if (nameColumn >= 0 && data.isNotEmpty && data.every((r) => names.contains(normalize(r[nameColumn])))) {
        mode = ImportMode.update;
      }
      _proposeAddress();
    }
  }

  /// the role of a new node: from the values of its row (autoRole) or this role
  static const autoRole = '@auto';

  /// the roles of the problem with the column of their main value (tpp: supplier - supply, customer - demand)
  List<(String, int)> get _roleColumns {
    final spec = state.spec;
    if (spec == null) return const [];
    final params = state.problem?.parameters ?? const <String, dynamic>{};
    return [
      for (final r in spec.activeRoles(params))
        if (r.mainField case final f? when mapping.contains(f.key)) (spec.nodeRole(r, params), mapping.indexOf(f.key)),
    ];
  }

  /// the role of a row can be taken from its values
  bool get canDetectRoles => kind == TableKind.nodes && _roleColumns.isNotEmpty;

  /// autoRole: the first role whose main value in the row is not 0 - else a transshipment node (network flow) or the
  /// last role of the problem
  String rowRole(List<String> row) {
    if (role != autoRole) return role ?? 'customer';
    for (final (r, i) in _roleColumns) {
      final text = row[i].trim();
      if (text.isEmpty) continue;
      final v = _num(text);
      if (v == null || v != 0) return r; // a value - also of several commodities
    }
    final roles = state.assignableRoles;
    return roles.contains('transit') ? 'transit' : (roles.isEmpty ? 'customer' : roles.last);
  }

  /// nodes without columns of the coordinates and of the address: the address of the name and the other columns -
  /// with a header those named as parts of an address (the name only without a street or a place), else all others
  void _proposeAddress() {
    if (['latitude', 'longitude', 'address'].any(mapping.contains)) return;
    final name = mapping.indexOf('name');
    final parts = <int>[];
    var street = false;
    for (var i = 0; i < width; i++) {
      if (mapping[i] != null) continue;
      if (!header) {
        if (data.any((r) => r[i].isNotEmpty)) parts.add(i);
        continue;
      }
      final h = _header(rows.first[i]);
      if (_streetParts.contains(h) || _placeParts.contains(h)) street = true;
      if (_streetParts.contains(h) || _placeParts.contains(h) || _otherParts.contains(h)) parts.add(i);
    }
    addressParts = [if (name >= 0 && !street) name, ...parts]..sort();
  }

  /// the header of a column of the table - or Spalte n
  String columnName(int i) =>
      header && rows.first[i].isNotEmpty ? rows.first[i] : state.strings('ui.import.column', {'n': i + 1});

  /// the address of a row made of the columns of addressParts
  String composedAddress(List<String> row) => [
    for (final i in addressParts) row[i].replaceAll(RegExp(r'\s+'), ' ').trim(),
  ].where((p) => p.isNotEmpty).join(', ');

  int get width => rows.isEmpty ? 0 : rows.first.length;

  /// the rows of the data - without the header
  List<List<String>> get data => header ? rows.skip(1).toList() : rows;

  /// first row of the data in the table (for the messages)
  int get _firstRow => header ? 2 : 1;

  String? _columnOf(String headerText) {
    final h = _header(headerText);
    if (h.isEmpty) return null;
    // the labels and keys first, then the further headers - Kapazität: the capacity of a candidate before the
    // throughput of a node
    for (final c in columns) {
      if (_header(state.strings(c.label)) == h || normalize(c.key) == h) return c.key;
    }
    for (final c in columns) {
      if (_aliasesOf(c).contains(h)) return c.key;
    }
    // the label of the same field in another problem type, e.g. Bedarf (vrp) for Nachfrage (tpp)
    for (final c in columns) {
      if (c.field != null && _otherLabels(c.key).contains(h)) return c.key;
    }
    // another form of the word: Kapazitäten for Kapazität, capacities for capacity
    for (final c in columns) {
      final names = {_header(state.strings(c.label)), normalize(c.key), ..._aliasesOf(c)};
      if (names.any((n) => _sameWord(h, n))) return c.key;
    }
    return null;
  }

  /// the further headers of a column - Kapazität the supply (tpp), with a throughput of the nodes (network flow) that
  List<String> _aliasesOf(TableColumn c) {
    final all = _aliases[c.key] ?? const <String>[];
    if (c.key != 'supply' || !columns.any((o) => o.key == 'maxCap')) return all;
    return [
      for (final a in all)
        if (a != 'kapazitat') a,
    ];
  }

  /// two forms of a word - plural and singular: the same beginning, at most three letters more at the end
  static bool _sameWord(String a, String b) {
    if (a.length < 5 || b.length < 5) return false;
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return i >= a.length - 3 && i >= b.length - 3;
  }

  Set<String> _otherLabels(String key) => {
    for (final spec in modules.values) ...[
      for (final r in spec.roles)
        for (final f in r.nodeFields)
          if (f.key == key) _header(state.strings(f.label)),
      for (final f in [...spec.nodeFields, ...spec.edgeFields])
        if (f.key == key) _header(state.strings(f.label)),
    ],
  };

  /// a header without its unit in brackets, e.g. Zeitfenster (Uhrzeit), Strecke (km)
  static String _header(String text) => normalize(text.replaceAll(RegExp(r'\(.*?\)'), ''));

  /// without a header: latitude and longitude from columns of numbers in their ranges, the first text column the name
  void _guessByValues() {
    if (kind != TableKind.nodes) {
      if (width >= 2) mapping = [..._edgeBase.map((c) => c.key).take(2), ...List.filled(width - 2, null)];
      return;
    }
    bool all(int i, bool Function(num v) test) => rows.every((r) {
      final v = parseNumber(r[i], decimalComma: _decimalComma);
      return v != null && test(v);
    });
    for (var i = 0; i < width; i++) {
      if (!mapping.contains('latitude') && all(i, (v) => v.abs() <= 90 && v is double)) {
        mapping[i] = 'latitude';
      } else if (!mapping.contains('longitude') && mapping.contains('latitude') && all(i, (v) => v.abs() <= 180)) {
        mapping[i] = 'longitude';
      } else if (!mapping.contains('name') && rows.every((r) => parseNumber(r[i]) == null && r[i].isNotEmpty)) {
        mapping[i] = 'name';
      }
    }
  }

  bool get _decimalComma => state.strings.number(1.5).contains(',');

  num? _num(String text) => parseNumber(text, decimalComma: _decimalComma);

  /// what the paste would do - the errors with their rows
  ImportCheck check() {
    // the columns of the values changed: one role for all
    if (role == autoRole && !canDetectRoles) role = state.problemRoles.lastOrNull ?? 'customer';
    final result = ImportCheck();
    final s = state;
    final scenario = s.scenario;
    final col = {for (final (i, k) in mapping.indexed) ?k: i};
    if (kind == TableKind.nodes && !col.containsKey('name')) {
      result.errors.add(const ImportError(0, 'ui.import.needsName'));
      return result;
    }
    if (kind == TableKind.edges && (!col.containsKey('from') || !col.containsKey('to'))) {
      result.errors.add(const ImportError(0, 'ui.import.needsFromTo'));
      return result;
    }
    // nodes by id and by name - also the ones added by this paste
    final byId = {for (final n in scenario.nodes) n.id: n.id};
    final byName = {for (final n in scenario.nodes) normalize(n.name): n.id};
    String? nodeId(String text) => byId[text.trim()] ?? byName[normalize(text)];
    final fields = {for (final c in columns) c.key: c};
    var nextId = 1;
    String newId() {
      while (byId.containsKey('N$nextId')) {
        nextId++;
      }
      return 'N${nextId++}';
    }

    for (final (r, row) in data.indexed) {
      final line = r + _firstRow;
      if (row.every((c) => c.isEmpty)) continue;
      String cell(String key) => col[key] == null ? '' : row[col[key]!];
      final errors = <ImportError>[];
      final values = <String, Object?>{}; // field key -> value (null: removed)
      for (final MapEntry(:key, :value) in col.entries) {
        final c = fields[key];
        if (c?.field == null) continue;
        final (v, error) = _value(c!.field!, row[value], nodeId);
        if (error != null) {
          errors.add(ImportError(line, error, {'column': state.strings(c.label), 'value': row[value]}));
        } else {
          values[key] = v;
        }
      }
      bool? flag(String key) {
        if (cell(key).isEmpty) return null;
        final b = _bool(cell(key));
        if (b == null) {
          errors.add(
            ImportError(line, 'ui.import.noYesNo', {'column': state.strings(fields[key]!.label), 'value': cell(key)}),
          );
        }
        return b;
      }

      if (kind == TableKind.nodes) {
        final name = cell('name');
        if (name.isEmpty) {
          errors.add(ImportError(line, 'ui.import.noName'));
        }
        final idText = cell('id');
        final existing = mode == ImportMode.update ? (byId[idText] ?? byName[normalize(name)]) : null;
        if (mode == ImportMode.update && existing == null) {
          errors.add(ImportError(line, 'ui.import.notFound', {'name': name.isEmpty ? idText : name}));
        }
        if (mode == ImportMode.add && idText.isNotEmpty && byId.containsKey(idText)) {
          errors.add(ImportError(line, 'ui.import.idExists', {'id': idText}));
        }
        num? coordinate(String key, num limit) {
          if (cell(key).isEmpty) return null;
          final v = _num(cell(key));
          if (v == null || v.abs() > limit) {
            errors.add(
              ImportError(line, 'ui.import.noCoordinate', {
                'column': state.strings(fields[key]!.label),
                'value': cell(key),
              }),
            );
            return null;
          }
          return v;
        }

        final lat = coordinate('latitude', 90), lon = coordinate('longitude', 180);
        final address = col.containsKey('address')
            ? cell('address')
            : (addressParts.isNotEmpty ? composedAddress(row) : null);
        // without coordinates: those of the address - for an existing node only if its address has changed
        final locate =
            (lat == null || lon == null) &&
            (address ?? '').isNotEmpty &&
            (existing == null || normalize(scenario.node(existing)!.address ?? '') != normalize(address!));
        if (existing == null && (lat == null || lon == null) && !locate && errors.isEmpty) {
          errors.add(ImportError(line, 'ui.import.noPosition', {'name': name}));
        }
        List<String>? roles;
        if (cell('roles').isNotEmpty) {
          roles = [];
          for (final part in cell('roles').split(RegExp(r'[,;/]'))) {
            final p = normalize(part);
            if (p.isEmpty) continue;
            final r = nodeRoles.where((r) => normalize(state.strings('role.$r')) == p || normalize(r) == p).firstOrNull;
            if (r == null) {
              errors.add(ImportError(line, 'ui.import.noRole', {'value': part.trim()}));
            } else {
              roles.add(r);
            }
          }
        }
        final active = flag('active');
        if (errors.isNotEmpty) {
          result.errors.addAll(errors);
          continue;
        }
        if (locate) result.toLocate.add((line, address!));
        if (existing != null) {
          result.updated++;
          result._changes.add((sc, _, located) {
            final n = sc.node(existing)!;
            n.name = name;
            if (lat != null && lon != null) n.position = LatLng(lat.toDouble(), lon.toDouble());
            if (located[line] case final p?) n.position = p;
            if (address != null) n.address = address;
            if (roles != null) n.roles = roles;
            if (active != null) n.active = active;
            values.forEach((k, v) => n[k] = v);
          });
        } else {
          final id = idText.isNotEmpty ? idText : newId();
          final newRole = rowRole(row);
          byId[id] = id;
          byName[normalize(name)] = id;
          result.added++;
          result._changes.add((sc, _, located) {
            final position =
                located[line] ?? (lat != null && lon != null ? LatLng(lat.toDouble(), lon.toDouble()) : null);
            if (position == null) return; // the address has not been found
            final n = sc.addNode(position, roles: roles ?? [newRole]);
            n.id = id;
            n.name = name;
            if (address != null && address.isNotEmpty) n.address = address;
            if (active == false) n.active = false;
            values.forEach((k, v) {
              if (v != null) n[k] = v;
            });
          });
        }
      } else {
        final net = s.network;
        final from = nodeId(cell('from')), to = nodeId(cell('to'));
        if (from == null) errors.add(ImportError(line, 'ui.import.unknownNode', {'value': cell('from')}));
        if (to == null) errors.add(ImportError(line, 'ui.import.unknownNode', {'value': cell('to')}));
        if (from != null && from == to) errors.add(ImportError(line, 'ui.import.sameNode', {'value': cell('from')}));
        final directed = flag('directed');
        if (net == null || errors.isNotEmpty) {
          result.errors.addAll(errors);
          continue;
        }
        final index = net.edges.indexWhere(
          (e) => (e.from == from && e.to == to) || (!e.directedIn(net) && e.from == to && e.to == from),
        );
        if (mode == ImportMode.update && index < 0) {
          result.errors.add(ImportError(line, 'ui.import.noEdge', {'from': cell('from'), 'to': cell('to')}));
          continue;
        }
        if (mode == ImportMode.add && index >= 0) {
          result.errors.add(ImportError(line, 'ui.import.edgeExists', {'from': cell('from'), 'to': cell('to')}));
          continue;
        }
        if (index >= 0) {
          result.updated++;
        } else {
          result.added++;
        }
        result._changes.add((sc, n, _) {
          final e = index >= 0 ? n!.edges[index] : n!.addEdge(from!, to!);
          if (directed != null) e['directed'] = directed == n.directed ? null : directed;
          values.forEach((k, v) => e[k] = v);
        });
      }
    }
    return result;
  }

  /// the value of a field from its cell - (value, null) or (null, message key of the error); empty: null (removed)
  (Object?, String?) _value(FieldSpec f, String text, String? Function(String) nodeId) {
    final t = state.strings;
    if (text.isEmpty) return (null, null);
    switch (f.kind) {
      case FieldKind.number || FieldKind.integer || FieldKind.unlimited:
        if (f.kind == FieldKind.unlimited &&
            RegExp(r'^(m|∞|unbegrenzt|unlimited|inf)$', caseSensitive: false).hasMatch(text)) {
          return ('M', null);
        }
        final v = _num(text);
        if (v == null) return (null, 'ui.import.noNumber');
        if (f.kind == FieldKind.integer && v != v.roundToDouble()) return (null, 'ui.import.noInteger');
        return (f.kind == FieldKind.integer ? v.round() : v, null);
      case FieldKind.boolean:
        final b = _bool(text);
        return b == null ? (null, 'ui.import.noYesNo') : (b, null);
      case FieldKind.choice:
        final n = normalize(text);
        final c = f.choices.where((c) => normalize(c) == n || normalize(t('choice.${f.key}.$c')) == n).firstOrNull;
        return c == null ? (null, 'ui.import.noChoice') : (c, null);
      case FieldKind.node:
        final id = nodeId(text);
        return id == null ? (null, 'ui.import.unknownNode') : (id, null);
      case FieldKind.timeWindow:
        final parts = text.split(RegExp(r'\s*[–—-]\s*|\s+bis\s+|\s+to\s+'));
        num? at(String p) => p.trim().isEmpty ? null : state.clock.parse(p) ?? _num(p);
        final a = at(parts[0]), b = parts.length > 1 ? at(parts[1]) : null;
        if (a == null && parts[0].trim().isNotEmpty || parts.length > 1 && b == null && parts[1].trim().isNotEmpty) {
          return (null, 'ui.import.noTimeWindow');
        }
        if (a != null && b != null && a > b) return (null, 'ui.import.noTimeWindow');
        return ([a, b], null);
      case FieldKind.text:
        return (text, null);
      case FieldKind.commodities || FieldKind.modes:
        return (null, null);
    }
  }

  static bool? _bool(String text) {
    final n = normalize(text);
    if (const ['ja', 'yes', 'si', 'oui', 'true', 'wahr', '1', 'x', 'j', 'y'].contains(n)) return true;
    if (const ['nein', 'no', 'non', 'false', 'falsch', '0', 'n'].contains(n)) return false;
    return null;
  }

  /// the paste - the coordinates of the addresses first, then the rows without errors at once; the number of added
  /// and updated nodes or edges. progress: (done, total) of the addresses; cancelled: stops looking them up
  Future<ImportCheck> apply({void Function(int, int)? progress, bool Function()? cancelled}) async {
    final result = check();
    if (result.isEmpty) return result;
    final located = await locate(
      state,
      result.toLocate,
      progress: progress,
      cancelled: cancelled,
      notFound: (line, address) {
        result.errors.add(ImportError(line, 'ui.import.addressNotFound', {'address': address}));
        // a new node without coordinates is left out, an existing one keeps its coordinates
        if (kind == TableKind.nodes && mode == ImportMode.add) result.added--;
      },
    );
    state.edit(() {
      for (final change in result._changes) {
        change(state.scenario, state.network, located);
      }
    });
    result.errors.sort((a, b) => a.row.compareTo(b.row));
    return result;
  }
}

/// the coordinates of addresses - the first hit of the geocoding (hits near the nodes first); key: the key given
Future<Map<K, LatLng>> locate<K>(
  AppState s,
  List<(K, String)> addresses, {
  void Function(int, int)? progress,
  bool Function()? cancelled,
  void Function(K, String)? notFound,
}) async {
  final located = <K, LatLng>{};
  for (final (i, (key, address)) in addresses.indexed) {
    if (cancelled?.call() ?? false) {
      notFound?.call(key, address);
      continue;
    }
    progress?.call(i, addresses.length);
    try {
      final hits = await s.geocode(address);
      if (hits.isNotEmpty) located[key] = hits.first.position;
    } catch (_) {
      // offline or no answer: as not found
    }
    if (!located.containsKey(key)) notFound?.call(key, address);
  }
  progress?.call(addresses.length, addresses.length);
  return located;
}

/// the coordinates of the nodes from their addresses - (found, the names of the nodes not found)
Future<(int, List<String>)> locateNodes(
  AppState s,
  List<Node> nodes, {
  void Function(int, int)? progress,
  bool Function()? cancelled,
}) async {
  final missing = <String>[];
  final located = await locate(
    s,
    [
      for (final n in nodes)
        if ((n.address ?? '').trim().isNotEmpty) (n.id, n.address!.trim()),
    ],
    progress: progress,
    cancelled: cancelled,
    notFound: (id, _) => missing.add(s.nameOf(id)),
  );
  if (located.isNotEmpty) {
    s.edit(() {
      for (final MapEntry(:key, :value) in located.entries) {
        s.scenario.node(key)?.position = value;
      }
    });
  }
  return (located.length, missing);
}
