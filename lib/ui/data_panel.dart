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
  const DataPanel({super.key, required this.state, required this.onSaveSolution});

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
        DataTab.solution => SolutionTab(state: s, onSave: onSaveSolution),
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
  FieldSpec('matrixSource', FieldKind.choice, choices: ['osm', 'beeline'], defaultValue: 'osm', required: true),
  FieldSpec(
    'travelmode',
    FieldKind.choice,
    choices: ['car', 'foot', 'wheelchair'],
    defaultValue: 'car',
    required: true,
  ),
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
            for (final f in spec.visibleParameters(values)) field(f, values),
          ],
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: Ui.gap),
          for (final e in errors) Text(t.message(e), style: const TextStyle(color: Ui.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        Text(t('ui.par.matrix'), style: Ui.title),
        const SizedBox(height: Ui.gap),
        FieldGrid(children: [for (final f in _matrixFields) field(f, s.scenario.matrix)]),
      ],
    );
  }
}
