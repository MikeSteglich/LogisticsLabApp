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
    final assignments = ((res?['assignments'] as List?) ?? const []).cast<Map<String, dynamic>>();
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
                    if (summary[col.key] case final num v)
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
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
              },
              children: [
                _row([
                  t('ui.sol.from'),
                  t('ui.sol.to'),
                  t('result.flow'),
                  t('result.rate'),
                  t('ui.sol.costs'),
                ], header: true),
                for (final (i, a) in assignments.indexed)
                  _row(selected: i == s.selectedFlow, onTap: () => s.selectFlow(i), [
                    name(a['from']),
                    name(a['to']),
                    t.number(a['flow'] as num),
                    t.fixed(a['rate'] as num, 2),
                    t.fixed((a['flow'] as num) * (a['rate'] as num), 2),
                  ]),
              ],
            ),
          ),
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
  static TableRow _row(List<String> cells, {bool header = false, bool selected = false, VoidCallback? onTap}) =>
      TableRow(
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
                  textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
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
      'multiple' => !u.sends && u.multiple,
      final f => f == 'notFull:${u.role}' && u.notFull,
    };
    final options = <(String, String, int)>[
      ('all', t('ui.filter.all'), a.uses.length),
      for (final r in roles) ('notFull:$r', t('ui.sol.notFull.$r'), a.ofRole(r).where((u) => u.notFull).length),
      ('multiple', t('ui.sol.multiple.${roles[1]}'), a.multipleReceivers),
    ];
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
    Widget bar(NodeUse u) {
      final share = u.share;
      if (share == null) return text('');
      // the bar takes the room the percentage leaves
      return Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60, minHeight: 6, maxHeight: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share,
                  backgroundColor: Ui.border,
                  color: u.notFull ? Ui.warning : Ui.roleColors(u.role).$1, // as on the map
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          text('${t.number(share * 100, decimals: 0)} %', color: u.notFull ? Ui.warning : Ui.text),
        ],
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
                cell(text(t('ui.sol.share'), bold: true, color: head), flex: 3),
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
                        child: text('${u.partners.length}', bold: u.multiple && !u.sends),
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
