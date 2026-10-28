/// Data area: tabs nodes, network, parameters and solution - built from the ModuleSpec of the problem.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../modules/modules.dart';
import 'network_tab.dart';
import 'nodes_tab.dart';
import 'solution_tab.dart';
import 'theme.dart';
import 'widgets.dart';

class DataPanel extends StatelessWidget {
  final AppState state;
  final VoidCallback onSaveSolution;
  final VoidCallback onExportSolution;
  const DataPanel({super.key, required this.state, required this.onSaveSolution, required this.onExportSolution});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final tabs = {
      DataTab.nodes: t('ui.tab.nodes'),
      DataTab.network: t('ui.tab.network'),
      DataTab.parameters: t('ui.tab.parameters'),
      DataTab.solution: t('ui.tab.solution'),
    };
    final Widget body;
    if (s.problem != null && s.spec == null) {
      body = _Note(t('ui.notYet', {'type': 'module.${s.problem!.type}'}));
    } else {
      body = switch (s.tab) {
        DataTab.nodes => NodesTab(state: s),
        DataTab.network => NetworkTab(state: s),
        DataTab.parameters => _ParametersTab(state: s),
        DataTab.solution => SolutionTab(state: s, onSave: onSaveSolution, onExport: onExportSolution),
      };
    }
    return ColoredBox(
      color: Ui.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ui.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final MapEntry(:key, :value) in tabs.entries) _Tab(value, key == s.tab, () => s.setTab(key)),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: Ui.minTarget,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? Ui.accent : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Ui.accent : Ui.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: const TextStyle(color: Ui.textSecondary)),
  );
}

//*************** parameters ************************************

const _matrixFields = [
  // road network from OSM: always by car (travelmode car of a new scenario) - other modes are of no use here
  FieldSpec('matrixSource', FieldKind.choice, choices: ['osm', 'beeline'], defaultValue: 'osm', required: true),
  FieldSpec('costPerKm', FieldKind.number, unit: '€', min: 0),
  FieldSpec('costPerHour', FieldKind.number, unit: '€', min: 0),
];

class _ParametersTab extends StatelessWidget {
  final AppState state;
  const _ParametersTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final p = s.problem;
    final spec = s.spec;
    if (p == null || spec == null) return _Note(t('ui.noProblem'));
    final values = p.parameters;
    // fields are recreated for another problem or language
    final k = '${p.name}|${t.language}';
    Widget field(FieldSpec f, Map<String, dynamic> target) => SpecField(
      scenario: s.scenario,
      measure: values['matrixMode'] as String?,
      // continuous location: the smallest capacity per location as suggestion
      // coverings: the smallest radius that covers every customer
      hintText: f.key == 'capacities' && s.minCapacity != null
          ? t('hint.minCapacity', {'min': t.number(s.minCapacity!)})
          : f.key == 'radius' && s.minRadius != null
          ? t('hint.minRadius', {'min': s.valueText(s.minRadius!, unit: s.coveringRadius!['unit'] as String?)})
          : null,
      suggestion: f.key == 'radius' ? s.minRadius : null,
      suggestionTooltip: f.key == 'radius' && s.minRadius != null
          ? t('hint.setMinRadius', {'min': s.valueText(s.minRadius!, unit: s.coveringRadius!['unit'] as String?)})
          : null,
      key: ValueKey('$k|${f.key}'),
      spec: f,
      value: target[f.key] ?? f.defaultValue,
      strings: t,
      onChanged: (v) => s.edit(() => v == null ? target.remove(f.key) : target[f.key] = v),
    );
    final errors = spec.validateParameters(values);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('ui.par.problem', {'type': spec.label}), style: Ui.title),
        const SizedBox(height: Ui.gap),
        FieldGrid(
          children: [
            TextValueField(
              key: ValueKey('$k|name'),
              label: t('ui.problemName'),
              value: p.name,
              error: p.name.trim().isEmpty ? t('error.required', {'label': 'ui.problemName'}) : null,
              onChanged: (v) {
                final name = v.trim();
                if (name.isEmpty || s.scenario.problems.any((q) => q.name == name && q != p)) return;
                s.edit(() {
                  final sol = s.solutions.remove(p.name);
                  p.name = name;
                  s.problemName = name;
                  if (sol != null) s.solutions[name] = sol;
                });
              },
            ),
            ..._pairedNodes([for (final f in spec.visibleParameters(values)) f], (f) => field(f, values)),
          ],
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: Ui.gap),
          for (final e in errors) Text(t.message(e), style: const TextStyle(color: Ui.error, fontSize: 13)),
        ],
        // commodities of a multi-commodity flow, modes of a multimodal flow - records of the scenario
        if (spec.usesCommodities) ...[
          const SizedBox(height: 20),
          _Records(
            kind: 'commodities',
            state: s,
            title: 'ui.commodities',
            add: 'ui.commodities.add',
            prefix: 'G',
            records: s.scenario.commodities,
            fields: _commodityFields,
          ),
        ],
        if (spec.usesVehicles) ...[
          const SizedBox(height: 20),
          _Records(
            kind: 'vehicles',
            state: s,
            title: 'ui.vehicles',
            add: 'ui.vehicles.add',
            prefix: 'V',
            records: s.scenario.vehicles,
            fields: _vehicleFields,
          ),
        ],
        if (spec.usesModes) ...[
          const SizedBox(height: 20),
          _Records(
            kind: 'modes',
            state: s,
            title: 'ui.modes',
            add: 'ui.modes.add',
            prefix: 'M',
            records: s.scenario.modes,
            fields: _modeFields,
          ),
        ],
        const SizedBox(height: 20),
        Text(t('ui.par.matrix'), style: Ui.title),
        const SizedBox(height: Ui.gap),
        FieldGrid(children: [for (final f in _matrixFields) field(f, s.scenario.matrix)]),
      ],
    );
  }
}

/// the parameter fields in the grid of two columns - two node fields in a row (start and end, source and sink)
/// side by side: an empty cell before them if they would start in the right column (the name of the problem is
/// the first cell)
List<Widget> _pairedNodes(List<FieldSpec> fields, Widget Function(FieldSpec) field) {
  final out = <Widget>[];
  var cells = 1; // the name of the problem
  for (final (i, f) in fields.indexed) {
    final pair = f.kind == FieldKind.node && i + 1 < fields.length && fields[i + 1].kind == FieldKind.node;
    if (pair && cells.isOdd) {
      out.add(const SizedBox.shrink());
      cells++;
    }
    out.add(field(f));
    // a wide field (switch, values per commodity) takes a whole row - after it a new row begins
    final wide = const {FieldKind.boolean, FieldKind.commodities, FieldKind.modes}.contains(f.kind);
    cells += wide ? (cells.isOdd ? 3 : 2) : 1;
  }
  return out;
}

const _vehicleFields = [
  FieldSpec('name', FieldKind.text),
  FieldSpec('capacity', FieldKind.number, required: true, min: 0),
  // empty: as many as needed - the solver uses as few tours as possible
  FieldSpec('count', FieldKind.integer, min: 1, hint: 'hint.auto'),
];
const _commodityFields = [
  FieldSpec('name', FieldKind.text),
  FieldSpec('costPerKm', FieldKind.number, unit: '€', min: 0),
  FieldSpec('costPerHour', FieldKind.number, unit: '€', min: 0),
  FieldSpec('capacityFactor', FieldKind.number, min: 0, defaultValue: 1.0),
];
const _modeFields = [
  FieldSpec('name', FieldKind.text),
  FieldSpec('costPerKm', FieldKind.number, unit: '€', min: 0),
  FieldSpec('costPerHour', FieldKind.number, unit: '€', min: 0),
  FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0),
  FieldSpec('minFlow', FieldKind.number, min: 0),
  FieldSpec('capacity', FieldKind.unlimited, min: 0),
];

/// Records of the scenario (commodities, modes): one block per record, the id is given and stays - nodes and edges
/// refer to it.
class _Records extends StatelessWidget {
  final AppState state;
  final String title;
  final String add;
  final String prefix;
  final List<Map<String, dynamic>> records;
  final List<FieldSpec> fields;
  final String kind; // commodities or modes
  const _Records({
    required this.kind,
    required this.state,
    required this.title,
    required this.add,
    required this.prefix,
    required this.records,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(t(title), style: Ui.title)),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(t(add)),
              onPressed: () => s.edit(() {
                final ids = {for (final r in records) r['id']};
                var i = records.length + 1;
                while (ids.contains('$prefix$i')) {
                  i++;
                }
                records.add({'id': '$prefix$i', 'name': '$prefix$i'});
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final r in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Section(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${t('ui.col.id')} ${r['id']}', style: Ui.small)),
                      IconButton(
                        tooltip: t('ui.records.delete'),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => s.deleteRecord(kind, r),
                      ),
                    ],
                  ),
                  FieldGrid(
                    columns: 3,
                    children: [
                      for (final f in fields)
                        if (f.key == 'name')
                          // the name shown in the solution - empty: the id
                          TextValueField(
                            key: ValueKey('${identityHashCode(r)}|name|${t.language}'),
                            label: t(f.label),
                            value: r['name'] as String? ?? '',
                            hint: '${r['id']}',
                            onChanged: (v) => s.edit(() => v.trim().isEmpty ? r.remove('name') : r['name'] = v),
                          )
                        else
                          SpecField(
                            key: ValueKey('${identityHashCode(r)}|${f.key}|${t.language}'),
                            spec: f,
                            value: r[f.key],
                            strings: t,
                            onChanged: (v) => s.edit(() => v == null || v == '' ? r.remove(f.key) : r[f.key] = v),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
