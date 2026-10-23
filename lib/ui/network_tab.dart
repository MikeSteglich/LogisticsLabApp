/// Network of the problem: choose or create it, edges as list (display only) and mask, all connections at once.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';
import 'theme.dart';
import 'widgets.dart';

const _newNetwork = '\u0000new';

class NetworkTab extends StatelessWidget {
  final AppState state;
  const NetworkTab({super.key, required this.state});

  static final _selectedRow = GlobalKey();

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _create(BuildContext context) async {
    final s = state;
    final t = s.strings;
    final taken = s.scenario.networks.keys.toSet();
    var name = s.problem?.name ?? '';
    for (var i = 2; taken.contains(name); i++) {
      name = '${s.problem?.name} $i';
    }
    var directed = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(t('ui.net.new')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextValueField(
                  label: t('ui.net.name'),
                  value: name,
                  error: taken.contains(name.trim()) ? t('ui.net.exists') : null,
                  onChanged: (v) => setDialog(() => name = v),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: directed,
                  title: Text(t('ui.net.directed')),
                  onChanged: (v) => setDialog(() => directed = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
            FilledButton(
              onPressed: name.trim().isEmpty || taken.contains(name.trim()) ? null : () => Navigator.pop(c, true),
              child: Text(t('ui.ok')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) s.newNetwork(name, directed: directed);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final p = s.problem;
    if (p == null) return const SizedBox.shrink();
    final nets = s.scenario.networks;
    final net = s.network;
    final spec = s.spec;
    final roles = spec?.activeRoles(p.parameters) ?? const <RoleSpec>[];

    final chooser = Row(
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DropdownButtonFormField<String?>(
              key: ValueKey('net-${p.name}-${p.network}-${nets.length}'),
              initialValue: nets.containsKey(p.network) ? p.network : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: t('ui.net.forProblem')),
              items: [
                DropdownMenuItem(value: null, child: Text(t('ui.net.none'))),
                for (final n in nets.values)
                  DropdownMenuItem(
                    value: n.name,
                    child: Text('${n.name} · ${t('ui.net.edges', {'n': n.edges.length})}'),
                  ),
                DropdownMenuItem(value: _newNetwork, child: Text(t('ui.net.new'))),
              ],
              onChanged: (v) => v == _newNetwork ? _create(context) : s.chooseNetwork(v),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: t('ui.net.help'),
          child: const Icon(Icons.info_outline, size: 18, color: Ui.textSecondary),
        ),
      ],
    );
    if (net == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(alignment: Alignment.topLeft, child: chooser),
      );
    }
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chooser,
        const SizedBox(height: 4),
        InkWell(
          onTap: () => s.edit(() => net.directed = !net.directed),
          child: Row(
            children: [
              Checkbox(value: net.directed, onChanged: (v) => s.edit(() => net.directed = v ?? true)),
              Flexible(
                child: Text(
                  t(spec?.edgeDirections == true ? 'ui.net.directedDefault' : 'ui.net.directed'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(t('ui.edge.add')),
              onPressed: () => _addEdge(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.timeline, size: 16),
              style: s.drawingEdge
                  ? OutlinedButton.styleFrom(
                      backgroundColor: Ui.accentLight,
                      side: const BorderSide(color: Ui.accent),
                    )
                  : null,
              label: Text(t('ui.edge.draw')),
              onPressed: () => s.setDrawingEdge(!s.drawingEdge),
            ),
            if (roles.length >= 2 || spec?.edgeDirections == true)
              Tooltip(
                message: spec?.edgeDirections == true
                    ? t('ui.edge.allNodesHint')
                    : s.transitCandidates.isEmpty
                    ? t('ui.edge.allHint', {
                        'from': 'role.${spec!.nodeRole(roles.first, p.parameters)}',
                        'to': 'role.${spec.nodeRole(roles.last, p.parameters)}',
                      })
                    : t('ui.edge.allHintTransit', {
                        'from': 'role.${spec!.nodeRole(roles.first, p.parameters)}',
                        'to': 'role.${spec.nodeRole(roles.last, p.parameters)}',
                      }),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.device_hub, size: 16),
                  label: Text(t('ui.edge.all')),
                  onPressed: () => _snack(context, t('ui.edge.added', {'n': s.addAllEdges()})),
                ),
              ),
            Tooltip(
              message: t('ui.edge.delete'),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero),
                onPressed: s.edge == null ? null : s.deleteEdge,
                child: const Icon(Icons.delete_outline, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
    return ListAndMask(
      header: header,
      list: Section(
        padding: EdgeInsets.zero,
        child: _EdgeTable(state: s, net: net, selectedKey: _selectedRow),
      ),
      mask: s.edge != null
          ? _EdgeMask(key: ValueKey('${identityHashCode(s.edge!.json)}|${t.language}'), state: s, edge: s.edge!)
          : Text(t('ui.edge.none'), style: const TextStyle(color: Ui.textSecondary)),
      selected: s.selectedEdge,
      selectedKey: _selectedRow,
      ratio: s.listRatio,
      onRatio: s.setListRatio,
      onRatioEnd: (v) => s.setListRatio(v, save: true),
      onRatioReset: () => s.setListRatio(AppState.defaultListRatio, save: true),
      semanticLabel: t('ui.split.list'),
    );
  }

  /// new edge, changed in the mask: from the first node of the first problem role (tpp: a supplier) to the first
  /// node of the second role it is not connected with yet - else any free connection
  void _addEdge(BuildContext context) {
    final s = state;
    final params = s.problem!.parameters;
    final roleNodes = [
      for (final r in s.spec?.activeRoles(params) ?? const <RoleSpec>[])
        [
          for (final n in s.scenario.nodes)
            if (n.roles.contains(s.spec!.nodeRole(r, params))) n.id,
        ],
    ];
    final all = [for (final n in s.scenario.nodes) n.id];
    final froms = roleNodes.isNotEmpty ? [...roleNodes[0], ...all] : all;
    final tos = roleNodes.length > 1 ? [...roleNodes[1], ...all] : all;
    for (final a in froms) {
      for (final b in tos) {
        if (s.addEdge(a, b)) return;
      }
    }
    _snack(context, s.strings('ui.edge.exists'));
  }
}

class _EdgeTable extends StatelessWidget {
  final AppState state;
  final Network net;
  final GlobalKey selectedKey;
  const _EdgeTable({required this.state, required this.net, required this.selectedKey});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final fields = s.spec?.edgeFields ?? const <FieldSpec>[];
    String name(String id) => s.scenario.node(id)?.name ?? id;
    // no modes at an edge: all modes of the scenario
    String value(Object? v, FieldSpec f) => s.fieldText(v) ?? (f.kind == FieldKind.modes ? t('ui.modes.all') : '');
    Widget cell(String text, {int flex = 2, bool right = false, bool bold = false, Color? color}) => Expanded(
      flex: flex,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? Ui.text,
          fontFeatures: Ui.tabular,
        ),
      ),
    );
    Widget row(List<Widget> cells, {Color? background, VoidCallback? onTap, bool selected = false}) => Material(
      color: background ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: Color(0xFFEEF0F3)),
              left: BorderSide(color: selected ? Ui.accent : Colors.transparent, width: 3),
            ),
          ),
          child: Row(
            children: [
              for (final c in cells) ...[c, const SizedBox(width: 8)],
            ],
          ),
        ),
      ),
    );
    final edges = net.edges;
    // the direction of each edge - head: that of the network, mixed: a dash
    final arrows = {for (final e in net.edges) e.arrowIn(net)};
    final arrow = arrows.length == 1 ? arrows.single : (net.directed ? '→' : '↔');
    return Column(
      children: [
        row([
          cell('${t('ui.net.from')} $arrow ${t('ui.net.to')}', flex: 5, bold: true, color: Ui.textSecondary),
          for (final f in fields) cell(t(f.label), right: true, bold: true, color: Ui.textSecondary),
        ], background: Ui.surfaceAlt),
        if (edges.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(t('ui.edge.empty'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
          ),
        for (final (i, e) in edges.indexed)
          Semantics(
            key: i == s.selectedEdge ? selectedKey : null, // the list scrolls to the selected edge
            button: true,
            selected: i == s.selectedEdge,
            child: row(
              [
                cell('${name(e.from)} ${e.arrowIn(net)} ${name(e.to)}', flex: 5, bold: i == s.selectedEdge),
                for (final f in fields) cell(value(e[f.key], f), right: true),
              ],
              selected: i == s.selectedEdge,
              background: i == s.selectedEdge ? Ui.accentLight : null,
              onTap: () => s.selectEdge(i),
            ),
          ),
      ],
    );
  }
}

class _EdgeMask extends StatelessWidget {
  final AppState state;
  final Edge edge;
  const _EdgeMask({super.key, required this.state, required this.edge});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final e = edge;
    final net = s.network!;
    final params = s.problem!.parameters;
    final nodes = s.scenario.nodes;
    String name(String id) => s.scenario.node(id)?.name ?? id;

    /// start or end of the edge - the connection must not exist yet
    Widget end(bool isFrom) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t(isFrom ? 'ui.net.from' : 'ui.net.to')),
        DropdownButtonFormField<String>(
          initialValue: isFrom ? e.from : e.to,
          isExpanded: true,
          items: [for (final n in nodes) DropdownMenuItem(value: n.id, child: Text('${n.id} · ${n.name}'))],
          onChanged: (v) {
            if (v == null) return;
            final (from, to) = isFrom ? (v, e.to) : (e.from, v);
            if (from == e.from && to == e.to) return;
            final problem = from == to || net.hasEdge(from, to)
                ? 'ui.edge.exists'
                : (s.edgeAllowed(from, to) ? null : 'ui.edge.direction');
            if (problem != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(t(problem)), behavior: SnackBarBehavior.floating));
              return;
            }
            s.edit(() => isFrom ? e.from = v : e.to = v);
          },
        ),
      ],
    );

    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text('${name(e.from)} ${e.arrowIn(net)} ${name(e.to)}', style: Ui.title),
              Text(t('ui.node.detail'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          FieldGrid(children: [end(true), end(false)]),
          // tsp, cpp: one way or both ways - the network gives the default
          if (s.spec?.edgeDirections == true) ...[
            const SizedBox(height: 14),
            FieldLabel(t('ui.edge.direction.label')),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(t('ui.edge.directed'))),
                ButtonSegment(value: false, label: Text(t('ui.edge.undirected'))),
              ],
              selected: {e.directedIn(net)},
              onSelectionChanged: (v) => s.edit(() {
                final directed = v.single;
                // only the difference to the network is kept in the file
                e['directed'] = directed == net.directed ? null : directed;
              }),
            ),
          ],
          if ((s.spec?.edgeFields ?? const <FieldSpec>[]).isNotEmpty) ...[
            const SizedBox(height: 14),
            FieldGrid(
              children: [
                for (final f in s.spec!.edgeFields)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SpecField(
                        scenario: s.scenario,
                        onEditRecords: () => s.setTab(DataTab.parameters),
                        spec: f,
                        value: e[f.key],
                        strings: t,
                        onChanged: (v) => s.edit(() => e[f.key] = v),
                      ),
                      // the value is kept, but the problem uses it only with its parameter
                      if (!f.isVisible(params) && f.requires != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                t('ui.edge.unused', {'param': 'field.${f.requires}'}),
                                style: const TextStyle(fontSize: 12, color: Ui.warning),
                              ),
                              TextButton(
                                onPressed: () => s.edit(() => params[f.requires!] = true),
                                child: Text(t('ui.edge.enable')),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
