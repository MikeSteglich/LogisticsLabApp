/// Solution of the problem: status, key figures and the connections - from the solution document (llsol).
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
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
    String money(num v) => '${t.fixed(v, 2)} €';
    final ok = sol.status == 'solution';
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
                      SizedBox(
                        width: w,
                        child: Section(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t(col.label), style: Ui.small, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  col.unit == '€' ? money(v) : t.number(v),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: Ui.tabular,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                for (final a in assignments)
                  _row([
                    name(a['from']),
                    name(a['to']),
                    t.number(a['flow'] as num),
                    t.fixed(a['rate'] as num, 2),
                    t.fixed((a['flow'] as num) * (a['rate'] as num), 2),
                  ]),
              ],
            ),
          ),
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

  static TableRow _row(List<String> cells, {bool header = false}) => TableRow(
    decoration: BoxDecoration(
      color: header ? Ui.surfaceAlt : null,
      border: header ? null : const Border(top: BorderSide(color: Color(0xFFEEF0F3))),
    ),
    children: [
      for (final (i, c) in cells.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Text(
            c,
            textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              fontWeight: header ? FontWeight.w600 : FontWeight.w400,
              color: header ? Ui.textSecondary : Ui.text,
              fontFeatures: Ui.tabular,
            ),
          ),
        ),
    ],
  );
}
