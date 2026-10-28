/// Solution of the problem: status, key figures and the connections - from the solution document (llsol).
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/core_texts.dart';
import '../model/scenario.dart';
import '../model/solution_analysis.dart';
import '../modules/modules.dart';
import '../model/table_io.dart';
import 'table_dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class SolutionTab extends StatelessWidget {
  final AppState state;
  final VoidCallback onSave;
  final VoidCallback onExport; // the solution as Excel file
  const SolutionTab({super.key, required this.state, required this.onSave, required this.onExport});

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
    final parts = s.solutionParts;
    String percent(Object? v) => v is num ? '${t.number(v * 100, decimals: 0)} %' : '';
    final open = s.openNodes;
    String name(Object? id) => s.scenario.node('$id')?.name ?? '$id';
    // unit of the objective and the costs: costs (€) or the unit of distances / times (matrixMode)
    final valueUnit = sol.document['valueUnit'] as String?;
    String money(num v) =>
        valueUnit == null || valueUnit == 'costs' ? '${t.fixed(v, 2)} €' : '${t.number(v)} $valueUnit';
    final objectiveKey = spec.objective?.call(s.problem?.parameters ?? const {});
    final weighted = s.objectiveWeighted;
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
    final warnings = coreWarnings(t, sol.document);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(t('ui.tab.solution'), style: Ui.title),
            // wide view: the data area wide, the map narrow - for large solutions
            IconButton(
              tooltip: t(s.wideData ? 'ui.sol.narrow' : 'ui.sol.wide'),
              icon: Icon(s.wideData ? Icons.close_fullscreen : Icons.open_in_full, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: s.toggleWideData,
            ),
            Text(
              t('ui.status.${sol.status}'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ok ? Ui.ok : Ui.error),
            ),
            if (sol.document['message'] case final String m when m.isNotEmpty && !ok)
              Text(coreMessage(t, m), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
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
                    if ((col.key == 'objVal' ? res['objVal'] : summary[col.key]) case final num v
                        when !_sameAs(v, col.hideIfSameAs, res, summary))
                      card(
                        w,
                        t(weighted && col.weightedLabelKey != null ? col.weightedLabelKey! : col.label),
                        // weighted: demand x distance - no unit
                        weighted && col.weightedLabelKey != null
                            ? t.fixed(v, 2)
                            : col.unit == '€'
                            ? money(v)
                            : col.unit == '@time'
                            ? s.clock.duration(v)
                            : col.unit == 'EUR'
                            ? '${t.fixed(v, 2)} €'
                            : col.unit == '×'
                            ? '${t.fixed(v, 2)} ×'
                            : col.unit == '%'
                            ? '${t.number(v * 100, decimals: 0)} %'
                            : t.number(v),
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
          // one commodity or mode: quantities and utilization of it - the map follows
          if (parts.isNotEmpty) ...[PartChooser(state: s), const SizedBox(height: 8)],
          if (s.isRoute)
            _Route(state: s)
          else if (spec.group == ModuleGroup.location && res['nodes'] != null)
            _Locations(state: s, money: money)
          else
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
                    _row(
                      numericFrom: withSplit ? 3 : 2,
                      selected: i == s.selectedFlow || s.touchesHighlighted(a),
                      onTap: () => s.selectFlow(i),
                      [
                        name(a['from']),
                        name(a['to']),
                        if (withSplit) s.split(a),
                        t.number(a['flow'] as num),
                        if (withRates) ...[
                          a['rate'] == null ? '' : t.fixed(a['rate'] as num, 2),
                          a['rate'] == null ? '' : t.fixed((a['flow'] as num) * (a['rate'] as num), 2),
                        ],
                        if (withUtilization) percent(a['utilization']),
                      ],
                    ),
                ],
              ),
            ),
          // warehouses of a multi-stage WLP
          if (open.isNotEmpty && spec.group != ModuleGroup.location) ...[
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
            OutlinedButton.icon(
              icon: const Icon(Icons.table_view_outlined, size: 16),
              label: Text(t('ui.export.button')),
              onPressed: onExport,
            ),
            // the tables for Excel without a file
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: Text(t('ui.copy.solution')),
              onPressed: res == null ? null : () => copyText(context, s, copySolution(s)),
            ),
          ],
        ),
      ],
    );
  }

  /// the value is the same as that of the other column - e.g. the plain sum of the distances without weights
  static bool _sameAs(num v, String? other, Map<String, dynamic> res, Map<String, dynamic> summary) {
    if (other == null) return false;
    final o = other == 'objVal' ? res['objVal'] : summary[other];
    return o is num && (v - o).abs() <= 1e-6 * (o.abs() > 1 ? o.abs() : 1);
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

/// the tour: its sections in order with their length and the length so far - a tap highlights the section on the map
class _Route extends StatelessWidget {
  final AppState state;
  const _Route({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    String name(Object? id) => s.scenario.node('$id')?.name ?? '$id';
    final legs = s.connections;
    final routes = ((s.solution?.results?['routes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    // chinese postman: the sections over edges traversed more than once; vrp: quantities, arrivals, waiting
    final withPasses = legs.any((a) => a['passes'] != null);
    final withAmounts = legs.any((a) => a['amount'] != null);
    // pickup and delivery: + picked up, − delivered and the load of the vehicle after the stop
    final withLoad = legs.any((a) => a['load'] != null);
    String amount(Object? q) =>
        q is num && q != 0 ? (withLoad ? '${q > 0 ? '+' : '−'}${t.number(q.abs())}' : (q > 0 ? t.number(q) : '')) : '';
    final withArrivals = legs.any((a) => a['arrival'] != null);
    final withWaiting = legs.any((a) => (a['waiting'] as num? ?? 0) > 0.5);
    final clock = s.clock;
    // vehicle routing with times: the schedule of every section as in LogisticsLab 5
    final schedule = legs.any((a) => a['departure'] != null);
    // arrival after the waiting: the start of the service - within the time window of the node
    num? ready(Map<String, dynamic> a) =>
        a['arrival'] is num ? (a['arrival'] as num) + (a['waiting'] as num? ?? 0) : null;
    String window(Object? id) {
      final n = s.scenario.node('$id');
      if (n == null) return '';
      return s.nodeData(n).where((e) => e.$1.kind == FieldKind.timeWindow).map((e) => e.$2).firstOrNull ?? '';
    }

    final withWindows = schedule && legs.any((a) => window(a['to']).isNotEmpty);
    Widget table(List<(int, Map<String, dynamic>)> part) {
      var sum = 0.0;
      String duration(Object? v) => v is num && v > 0.5 ? clock.duration(v) : '';
      String time(Object? v) => v is num ? clock.format(v) : '';
      final head = schedule
          ? [
              t('ui.sol.leg'),
              t('ui.sol.from'),
              t('ui.sol.to'),
              t('ui.sol.departure'),
              t('ui.sol.travelTime'),
              t('ui.sol.waiting'),
              t('ui.sol.arrival'),
              if (withWindows) t('ui.col.timeWindow'),
              t('ui.sol.service'),
              t('ui.sol.amount'),
              if (withLoad) t('ui.sol.load'),
              t('ui.sol.distance'),
            ]
          : [
              t('ui.sol.leg'),
              t('ui.sol.from'),
              t('ui.sol.to'),
              if (withAmounts) t('ui.sol.amount'),
              if (withLoad) t('ui.sol.load'),
              t('ui.sol.legValue'),
              t('ui.sol.cumulated'),
              if (withWaiting) t('ui.sol.waiting'),
              if (withArrivals) t('ui.sol.arrival'),
              if (withPasses) t('ui.sol.passes'),
            ];
      List<String> cells(Map<String, dynamic> a, num v) => schedule
          ? [
              '${a['leg']}',
              name(a['from']),
              name(a['to']),
              time(a['departure']),
              duration(a['travel']),
              duration(a['waiting']),
              time(ready(a)),
              if (withWindows) window(a['to']),
              duration(a['service']),
              amount(a['amount']),
              if (withLoad) a['load'] is num ? t.number(a['load'] as num) : '',
              s.valueText(v),
            ]
          : [
              '${a['leg']}',
              name(a['from']),
              [name(a['to']), s.via(a)].where((x) => x.isNotEmpty).join('\n'),
              if (withAmounts) amount(a['amount']),
              if (withLoad) a['load'] is num ? t.number(a['load'] as num) : '',
              s.valueText(v),
              s.valueText(sum += v),
              if (withWaiting) duration(a['waiting']),
              if (withArrivals) time(ready(a)),
              if (withPasses) a['passes'] == null ? '' : '${a['pass']}/${a['passes']}',
            ];
      return Section(
        padding: EdgeInsets.zero,
        child: WideTable(
          rows: [
            SolutionTab._row(numericFrom: 3, header: true, head),
            for (final (i, a) in part)
              if (a['value'] case final num v)
                SolutionTab._row(
                  numericFrom: 3,
                  selected: i == s.selectedFlow || s.touchesHighlighted(a),
                  onTap: () => s.selectFlow(i),
                  cells(a, v),
                ),
          ],
        ),
      );
    }

    final indexed = [for (final (i, a) in legs.indexed) (i, a)];
    // vehicle routing: an overview of the tours and a table per tour
    if (routes.isEmpty || routes.first['capacity'] == null) return table(indexed);
    final names = s.routeNames;
    final many = routes.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('ui.sol.overview'), style: Ui.title),
        const SizedBox(height: 8),
        _Overview(state: s, routes: routes),
        const SizedBox(height: 16),
        for (final (ri, r) in routes.indexed) ...[
          if (ri > 0) const SizedBox(height: 14),
          Row(
            children: [
              if (many) ...[
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Ui.routeColors[ri % Ui.routeColors.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  [
                    ri < names.length ? names[ri] : '',
                    if (r['load'] is num) '${t('ui.sol.amount')} ${t.number(r['load'] as num)}',
                    if (r['distance'] is num) s.valueText(r['distance'] as num),
                    if (r['start'] is num && r['end'] is num)
                      '${clock.format(r['start'] as num)} – ${clock.format(r['end'] as num)}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          table([
            for (final e in indexed)
              if (e.$2['route'] == ri) e,
          ]),
        ],
        // pickup and delivery: the rides - direct and real time in the vehicle, the detour
        if (s.solution?.results?['requests'] case final List requests when requests.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(t('ui.sol.rides'), style: Ui.title),
          const SizedBox(height: 8),
          _Rides(state: s, requests: requests.cast<Map<String, dynamic>>()),
        ],
      ],
    );
  }
}

/// pickup and delivery (dial-a-ride): every pair with its tour, quantity, direct ride, ride in the vehicle and detour
class _Rides extends StatelessWidget {
  final AppState state;
  final List<Map<String, dynamic>> requests;
  const _Rides({required this.state, required this.requests});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    String name(Object? id) => s.scenario.node('$id')?.name ?? '$id';
    final names = s.routeNames;
    final routes = ((s.solution?.results?['routes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    String tour(Object? vehicle) {
      final i = routes.indexWhere((r) => r['vehicle'] == vehicle);
      return i < 0 || i >= names.length ? '${vehicle ?? ''}' : names[i];
    }

    return Section(
      padding: EdgeInsets.zero,
      child: WideTable(
        rows: [
          SolutionTab._row(numericFrom: 3, header: true, [
            t('role.pickup'),
            t('role.delivery'),
            t('ui.sol.tourVehicle'),
            t('ui.sol.amount'),
            t('ui.sol.direct'),
            t('ui.sol.ride'),
            t('ui.sol.detour'),
          ]),
          for (final q in requests)
            SolutionTab._row(
              numericFrom: 3,
              onTap: () {
                final i = routes.indexWhere((r) => r['vehicle'] == q['vehicle']);
                if (i >= 0 && i != s.selectedRoute) s.selectRoute(i);
              },
              [
                name(q['pickup']),
                name(q['delivery']),
                tour(q['vehicle']),
                t.number(q['amount'] as num? ?? 0),
                s.clock.duration(q['direct'] as num? ?? 0),
                s.clock.duration(q['ride'] as num? ?? 0),
                q['detour'] is num ? '${t.fixed(q['detour'] as num, 2)} ×' : '',
              ],
            ),
        ],
      ),
    );
  }
}

/// overview of the tours of a vehicle routing: stops, quantity and utilization, distance, driving time, start and return -
/// a row per tour and the total
class _Overview extends StatelessWidget {
  final AppState state;
  final List<Map<String, dynamic>> routes;
  const _Overview({required this.state, required this.routes});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final clock = s.clock;
    final names = s.routeNames;
    final withTimes = routes.any((r) => r['duration'] is num);
    num total(String key) => routes.fold<num>(0, (sum, r) => sum + (r[key] as num? ?? 0));
    String percent(num? v) => v == null ? '' : '${t.number(v * 100, decimals: 0)} %';
    List<String> row(String name, Map<String, dynamic> r) => [
      name,
      '${r['stops'] ?? ''}',
      t.number(r['load'] as num? ?? 0),
      percent(r['utilization'] as num?),
      s.valueText(r['distance'] as num? ?? 0),
      if (withTimes) ...[
        // total time of the tour: driving, waiting and service
        clock.duration(r['duration'] as num? ?? 0),
        r['start'] is num && r['end'] is num
            ? '${clock.format(r['start'] as num)} – ${clock.format(r['end'] as num)}'
            : '',
      ],
    ];
    final capacity = total('capacity');
    final sum = {
      'stops': total('stops'),
      'load': total('load'),
      'utilization': capacity > 0 ? total('load') / capacity : null,
      'distance': total('distance'),
      'duration': total('duration'),
    };
    // the whole width - scrolls sideways if the data area is narrow
    return Section(
      padding: EdgeInsets.zero,
      child: WideTable(
        rows: [
          SolutionTab._row(numericFrom: 1, header: true, [
            t('ui.sol.tourVehicle'),
            t('ui.sol.stops'),
            t('ui.sol.amount'),
            t('ui.sol.utilization'),
            t('ui.sol.distance'),
            if (withTimes) ...[t('ui.sol.totalTime'), t('ui.sol.time')],
          ]),
          // a click: the tour highlighted on the map
          for (final (i, r) in routes.indexed)
            SolutionTab._row(
              numericFrom: 1,
              selected: i == s.selectedRoute,
              onTap: () => s.selectRoute(i),
              row(i < names.length ? names[i] : '', r),
            ),
          if (routes.length > 1) SolutionTab._row(numericFrom: 1, header: true, row(t('ui.sol.total'), sum)),
        ],
      ),
    );
  }
}

/// all commodities or modes together, or one of them - the solution and the node list share the choice
class PartChooser extends StatelessWidget {
  final AppState state;
  const PartChooser({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(t(s.spec?.usesModes == true ? 'ui.sol.perMode' : 'ui.sol.perCommodity'), style: Ui.small),
        for (final (id, label) in [
          (null, t('ui.filter.all')),
          for (final p in s.solutionParts) (p['id'] as String?, Scenario.recordName(p)),
        ])
          ChoiceChip(
            label: Text(label),
            selected: s.solutionPart == id,
            labelStyle: TextStyle(
              color: s.solutionPart == id ? Ui.accentDark : Ui.textMuted,
              fontWeight: s.solutionPart == id ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(color: s.solutionPart == id ? Ui.accent : Ui.inputBorder),
            onSelected: (_) => s.setSolutionPart(id),
          ),
      ],
    );
  }
}

/// discrete location: the candidates (open or not, customers, quantity, capacity, opening costs) and the assignments
/// of the customers - maximal covering: the customers outside the radius of every open location
class _Locations extends StatelessWidget {
  final AppState state;
  final String Function(num) money; // a value in the unit of the matrix
  const _Locations({required this.state, required this.money});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final res = s.solution!.results!;
    String name(Object? id) => s.nameOf('$id');
    String percent(Object? v) => v is num ? '${t.number(v * 100, decimals: 0)} %' : '';
    final nodes = (res['nodes'] as Map).cast<String, dynamic>();
    // the open locations first
    // continuous location: the locations found are open
    int open(String id) => (nodes[id]['open'] as int?) ?? 1;
    final ids = nodes.keys.toList()..sort((a, b) => open(b).compareTo(open(a)));
    final found = s.foundLocations;
    final withCapacity = nodes.values.any((n) => n['capacity'] != null);
    final withFixed = nodes.values.any((n) => n['fixedCost'] != null);
    final assignments = s.connections;
    final withCosts = assignments.any((a) => a['costs'] != null);
    // multi-source: the share of the demand of the customer
    final withShares = assignments.any((a) => a['share'] != null);
    // the part of an assignment of the objective: costs (wlp), weighted: demand x distance without a unit
    final weighted = s.objectiveWeighted;
    final isCosts = s.solution!.document['valueUnit'] == 'costs' || s.problem?.type == 'wlp';
    String rating(num v) => weighted ? t.fixed(v, 2) : money(v);
    final assigned = {for (final a in assignments) a['to']};
    final customers = s.spec!.nodeRole(s.spec!.roles.last, s.problem?.parameters ?? const {});
    final uncovered = [
      for (final n in s.scenario.nodes)
        if (n.active && n.roles.contains(customers) && !assigned.contains(n.id)) n.name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('ui.sol.locations'), style: Ui.title),
        const SizedBox(height: 8),
        Section(
          padding: EdgeInsets.zero,
          child: WideTable(
            rows: [
              SolutionTab._row(numericFrom: 2, header: true, [
                t('ui.sol.location'),
                t('ui.sol.status'),
                t('ui.sol.customers'),
                t('ui.sol.amount'),
                if (withCapacity) ...[t('field.capacity'), t('ui.sol.utilization')],
                if (withFixed) t('field.openingCost'),
                // continuous location: where the locations are
                if (found.isNotEmpty) t('ui.col.coords'),
              ]),
              for (final id in ids)
                if ((nodes[id] as Map).cast<String, dynamic>() case final n)
                  SolutionTab._row(
                    numericFrom: 2,
                    selected: id == s.highlightedNode,
                    onTap: () => s.highlightNode(id),
                    [
                      name(id),
                      t(open(id) == 1 ? 'ui.sol.isOpen' : 'ui.sol.isClosed'),
                      open(id) == 1 ? '${n['nrOfAssigned'] ?? 0}' : '',
                      open(id) == 1 ? t.number(n['load'] as num? ?? 0) : '',
                      if (withCapacity) ...[
                        n['capacity'] is num ? t.number(n['capacity'] as num) : '',
                        percent(n['utilization']),
                      ],
                      if (withFixed) n['fixedCost'] is num ? '${t.fixed(n['fixedCost'] as num, 2)} €' : '',
                      if (found.isNotEmpty)
                        if (found[id] case final p?) '${t.fixed(p.latitude, 5)} / ${t.fixed(p.longitude, 5)}' else '',
                    ],
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(t('ui.sol.assignments'), style: Ui.title),
        const SizedBox(height: 8),
        Section(
          padding: EdgeInsets.zero,
          child: WideTable(
            rows: [
              SolutionTab._row(numericFrom: 2, header: true, [
                t('ui.sol.location'),
                t('role.customer'),
                t('ui.sol.amount'),
                if (withShares) t('ui.sol.share'),
                // the value of an assignment in the measure of the problem: distance, time or cost rate
                t(switch (s.solution!.document['valueUnit']) {
                  'costs' => 'result.rate',
                  final u when u == s.scenario.units['time'] => 'ui.sol.travelTime',
                  _ => 'ui.sol.value',
                }),
                if (withCosts) t(isCosts && !weighted ? 'ui.sol.costs' : 'ui.sol.rating'),
              ]),
              for (final (i, a) in assignments.indexed)
                SolutionTab._row(
                  numericFrom: 2,
                  selected: i == s.selectedFlow || s.touchesHighlighted(a),
                  onTap: () => s.selectFlow(i),
                  [
                    name(a['from']),
                    name(a['to']),
                    t.number(a['flow'] as num? ?? 0),
                    if (withShares) percent(a['share']),
                    a['value'] is num ? money(a['value'] as num) : '',
                    if (withCosts) a['costs'] is num ? rating(a['costs'] as num) : '',
                  ],
                ),
            ],
          ),
        ),
        // continuous location: the locations found as candidates of the scenario
        if (found.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: Text(t('ui.sol.adoptLocations')),
              onPressed: s.adoptFoundLocations,
            ),
          ),
        ],
        // maximal covering: outside the radius of every open location
        if (uncovered.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            t('ui.sol.uncovered', {'nodes': uncovered.join(', ')}),
            style: const TextStyle(fontSize: 13, color: Ui.warning),
          ),
        ],
      ],
    );
  }
}
