/// Solution of the problem: status, key figures and the connections - from the solution document (llsol).
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/solution_analysis.dart';
import 'theme.dart';
import 'widgets.dart';

class SolutionTab extends StatelessWidget {
  final AppState state;
  final VoidCallback onSave;
  const SolutionTab({super.key, required this.state, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final spec = s.spec!;
    final sol = s.solution;
    if (sol == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t('ui.sol.none'), style: const TextStyle(color: Ui.textSecondary)),
      );
    }
    final res = sol.results;
    final summary = (res?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final assignments = s.connections;
    // cost rates: tpp, min cost flow, multi-stage WLP - split per commodity or mode: multicommodity, multimodal
    final withRates = assignments.any((a) => a['rate'] != null);
    final withSplit = assignments.any((a) => a['flows'] != null || a['modes'] != null);
    final withUtilization = assignments.any((a) => a['utilization'] != null);
    String percent(Object? v) => v is num ? '${t.number(v * 100, decimals: 0)} %' : '';
    final open = s.openNodes;
    String name(Object? id) => s.scenario.node('$id')?.name ?? '$id';
    // unit of the objective and the costs: costs (€) or the unit of distances / times (matrixMode)
    final valueUnit = sol.document['valueUnit'] as String?;
    String money(num v) =>
        valueUnit == null || valueUnit == 'costs' ? '${t.fixed(v, 2)} €' : '${t.number(v)} $valueUnit';
    final objectiveKey = spec.objective?.call(s.problem?.parameters ?? const {});
    final ok = sol.status == 'solution';
    final analysis = s.analysis;
    // the value of the objective function: blue frame and note
    // the value of the objective function: blue frame with a note on its top edge
    Widget card(double w, String label, String value, {bool warn = false, bool objective = false}) => SizedBox(
      width: w,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: w,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: objective ? Ui.accentLight : Ui.surface,
              border: Border.all(color: objective ? Ui.accent : Ui.border, width: objective ? 2 : 1),
              borderRadius: BorderRadius.circular(Ui.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Ui.small, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFeatures: Ui.tabular,
                      color: warn ? Ui.warning : Ui.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (objective)
            Positioned(
              top: -8,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Ui.accent, borderRadius: BorderRadius.circular(3)),
                child: Text(
                  t('ui.sol.objective'),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
    final warnings = [for (final w in (sol.document['warnings'] as List? ?? const [])) '$w'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(t('ui.tab.solution'), style: Ui.title),
            Text(
              t('ui.status.${sol.status}'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ok ? Ui.ok : Ui.error),
            ),
            if (sol.document['message'] case final String m when m.isNotEmpty && !ok)
              Text(m, style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
          ],
        ),
        if (s.solutionIsStale) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Ui.warning),
              const SizedBox(width: 6),
              Flexible(
                child: Text(t('ui.sol.stale'), style: const TextStyle(fontSize: 13, color: Ui.warning)),
              ),
            ],
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final w in warnings) Text(w, style: const TextStyle(fontSize: 13, color: Ui.warning)),
        ],
        if (res != null) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < 420 ? 2 : 3;
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final col in spec.summary)
                    if ((col.key == 'objVal' ? res['objVal'] : summary[col.key]) case final num v)
                      card(
                        w,
                        t(col.label),
                        col.unit == '€' ? money(v) : t.number(v),
                        objective: col.key == objectiveKey,
                      ),
                  // how the nodes are served: supply left, demand not met, customers with several suppliers
                  if (analysis != null) ...[
                    for (final (i, role) in analysis.roles.take(2).indexed)
                      card(
                        w,
                        t('ui.sol.missing.$role'),
                        t.number(analysis.missing(role)),
                        warn: i == 1 && analysis.missing(role) > 0,
                      ),
                    if (analysis.roles.length > 1)
                      card(w, t('ui.sol.multipleCount.${analysis.roles[1]}'), '${analysis.multipleReceivers}'),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Section(
            padding: EdgeInsets.zero,
            child: Table(
              columnWidths: {
                0: const FlexColumnWidth(3),
                1: const FlexColumnWidth(3),
                if (withSplit) 2: const FlexColumnWidth(4),
              },
              // numbers as wide as their header or values - the names take the rest
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                _row(numericFrom: withSplit ? 3 : 2, header: true, [
                  t('ui.sol.from'),
                  t('ui.sol.to'),
                  if (withSplit) t(s.spec!.usesModes ? 'ui.modes' : 'ui.commodities'),
                  t('result.flow'),
                  if (withRates) ...[s.rateLabels.$1, s.rateLabels.$2],
                  if (withUtilization) t('ui.sol.utilization'),
                ]),
                for (final (i, a) in assignments.indexed)
                  _row(numericFrom: withSplit ? 3 : 2, selected: i == s.selectedFlow, onTap: () => s.selectFlow(i), [
                    name(a['from']),
                    name(a['to']),
                    if (withSplit) s.split(a),
                    t.number(a['flow'] as num),
                    if (withRates) ...[
                      a['rate'] == null ? '' : t.fixed(a['rate'] as num, 2),
                      a['rate'] == null ? '' : t.fixed((a['flow'] as num) * (a['rate'] as num), 2),
                    ],
                    if (withUtilization) percent(a['utilization']),
                  ]),
              ],
            ),
          ),
          // warehouses of a multi-stage WLP
          if (open.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t('ui.sol.open'), style: Ui.title),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(:key, :value) in open.entries)
                  Chip(
                    avatar: Icon(
                      value ? Icons.check_circle : Icons.cancel_outlined,
                      size: 16,
                      color: value ? Ui.ok : Ui.pale,
                    ),
                    label: Text('${name(key)} · ${t(value ? 'ui.sol.isOpen' : 'ui.sol.isClosed')}'),
                  ),
              ],
            ),
          ],
          if (analysis != null) ...[
            const SizedBox(height: 20),
            Text(t('ui.tab.nodes'), style: Ui.title),
            const SizedBox(height: 8),
            _NodeUses(state: s, analysis: analysis),
          ],
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.save_alt, size: 16),
              label: Text(t('ui.sol.save')),
              onPressed: onSave,
            ),
          ],
        ),
      ],
    );
  }

  /// row of the connections - a tap highlights the connection on the map (orange)
  static TableRow _row(
    List<String> cells, {
    bool header = false,
    bool selected = false,
    VoidCallback? onTap,
    int numericFrom = 2, // first column with numbers - right aligned
  }) => TableRow(
    decoration: BoxDecoration(
      color: header ? Ui.surfaceAlt : (selected ? Ui.highlightLight : null),
      border: header
          ? null
          : Border(
              top: const BorderSide(color: Color(0xFFEEF0F3)),
              left: BorderSide(color: selected ? Ui.highlight : Colors.transparent, width: 3),
            ),
    ),
    children: [
      for (final (i, c) in cells.indexed)
        TableRowInkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Text(
              c,
              textAlign: i >= numericFrom ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 13,
                fontWeight: header || selected ? FontWeight.w600 : FontWeight.w400,
                color: header ? Ui.textSecondary : (selected ? Ui.highlight : Ui.text),
                fontFeatures: Ui.tabular,
              ),
            ),
          ),
        ),
    ],
  );
}

/// The nodes in the solution: target, actual quantity, share and partners - with a filter, e.g. demand not met.
class _NodeUses extends StatefulWidget {
  final AppState state;
  final SolutionAnalysis analysis;
  const _NodeUses({required this.state, required this.analysis});

  @override
  State<_NodeUses> createState() => _NodeUsesState();
}

class _NodeUsesState extends State<_NodeUses> {
  String _filter = 'all'; // all, notFull:<role>, multiple

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final a = widget.analysis;
    final t = s.strings;
    final roles = a.roles.take(2).toList();
    bool passes(NodeUse u) => switch (_filter) {
      'all' => true,
      'multiple' => u.multipleReceiver,
      'through' => u.through,
      'full' => u.full,
      final f => f == 'notFull:${u.role}' && u.notFull && !u.through,
    };
    final through = a.through.length;
    final full = a.uses.where((u) => u.full).length;
    final options = <(String, String, int)>[
      ('all', t('ui.filter.all'), a.uses.length),
      for (final r in roles)
        ('notFull:$r', t('ui.sol.notFull.$r'), a.ofRole(r).where((u) => u.notFull && !u.through).length),
      if (roles.length > 1) ('multiple', t('ui.sol.multiple.${roles[1]}'), a.multipleReceivers),
      if (through > 0) ('through', t('role.transit.plural'), through),
      if (full > 0) ('full', t('ui.sol.full'), full),
    ];
    if (!options.any((o) => o.$1 == _filter)) _filter = 'all';
    final withUtilization = a.through.any((u) => u.utilization != null);
    final shown = a.uses.where(passes).toList();
    String name(String id) => s.scenario.node(id)?.name ?? id;

    Widget cell(Widget child, {int flex = 2, bool right = false}) => Expanded(
      flex: flex,
      child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: child),
    );
    Text text(String v, {bool bold = false, Color? color}) => Text(
      v,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color ?? Ui.text,
        fontFeatures: Ui.tabular,
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
    // share of the target (supply, demand) - nodes passing quantities through: utilization of their capacity
    Widget bar(NodeUse u) {
      final share = u.through ? u.utilization?.clamp(0, 1).toDouble() : u.share;
      if (share == null) return text('');
      final warn = u.through ? u.full : u.notFull;
      // the bar takes the room the percentage leaves
      final bar = Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60, minHeight: 6, maxHeight: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share,
                  backgroundColor: Ui.border,
                  color: warn ? Ui.warning : Ui.roleColors(u.role).$1, // as on the map
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          text('${t.number(share * 100, decimals: 0)} %', color: warn ? Ui.warning : Ui.text),
        ],
      );
      if (!u.through) return bar;
      return Tooltip(
        message:
            '${t('ui.sol.utilization')} ${t.number(u.utilization! * 100, decimals: 0)} % '
            '${t('ui.sol.ofCapacity', {'capacity': t.number(u.capacity ?? 0)})}',
        child: bar,
      );
    }

    const head = Ui.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (f, label, count) in options)
              ChoiceChip(
                label: Text('$label  $count'),
                selected: _filter == f,
                labelStyle: TextStyle(
                  color: _filter == f ? Ui.accentDark : Ui.textMuted,
                  fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: Ui.tabular,
                ),
                side: BorderSide(color: _filter == f ? Ui.accent : Ui.inputBorder),
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Section(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              row([
                cell(text(t('ui.col.name'), bold: true, color: head), flex: 3),
                cell(text(t('ui.col.roles'), bold: true, color: head)),
                cell(text(t('ui.sol.target'), bold: true, color: head), right: true),
                cell(text(t('ui.sol.actual'), bold: true, color: head), right: true),
                cell(
                  text(withUtilization ? t('ui.sol.shareOrUtilization') : t('ui.sol.share'), bold: true, color: head),
                  flex: 3,
                ),
                cell(text(t('ui.sol.partners'), bold: true, color: head), flex: 1, right: true),
              ], background: Ui.surfaceAlt),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(t('ui.sol.noNodes'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
                ),
              for (final u in shown)
                row(
                  [
                    cell(text(u.node.name, bold: u.node.id == s.selectedNode), flex: 3),
                    cell(text(t('role.${u.role}'), color: Ui.textMuted)),
                    cell(text(u.target == null ? '' : t.number(u.target!)), right: true),
                    cell(text(t.number(u.actual)), right: true),
                    cell(bar(u), flex: 3),
                    cell(
                      Tooltip(
                        message: u.partners.map((p) => '${name(p.$1)}: ${t.number(p.$2)}').join('\n'),
                        child: text('${u.partners.length}', bold: u.multipleReceiver),
                      ),
                      flex: 1,
                      right: true,
                    ),
                  ],
                  selected: u.node.id == s.selectedNode,
                  background: u.node.id == s.selectedNode ? Ui.accentLight : null,
                  onTap: () => s.selectNode(u.node.id, keepTab: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
