/// Data variants: other quantities, capacities and costs of the nodes and edges in the same file - each problem
/// chooses its variant, without one it uses the base values.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

const _newVariant = '\u0000new';

/// the data variant of the problem - the base, a variant or a new one; rename and delete
class VariantChooser extends StatelessWidget {
  final AppState state;
  const VariantChooser({super.key, required this.state});

  /// a name for a new or renamed variant - null if cancelled
  Future<String?> _askName(BuildContext context, String title, String name) async {
    final t = state.strings;
    final taken = {for (final v in state.scenario.variants) (v['name'] as String?)?.trim() ?? ''}..remove(name.trim());
    var value = name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: TextValueField(
              label: t('ui.variant.name'),
              value: value,
              error: taken.contains(value.trim()) ? t('ui.variant.exists') : null,
              onChanged: (v) => setDialog(() => value = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
            FilledButton(
              onPressed: value.trim().isEmpty || taken.contains(value.trim()) ? null : () => Navigator.pop(c, true),
              child: Text(t('ui.ok')),
            ),
          ],
        ),
      ),
    );
    return ok == true ? value.trim() : null;
  }

  Future<void> _create(BuildContext context) async {
    final s = state;
    final t = s.strings;
    final names = {for (final v in s.scenario.variants) v['name']};
    var n = s.scenario.variants.length + 1;
    while (names.contains(t('ui.variant.defaultName', {'n': n}))) {
      n++;
    }
    final name = await _askName(context, t('ui.variant.new'), t('ui.variant.defaultName', {'n': n}));
    if (name != null) s.newVariant(name);
  }

  Future<void> _delete(BuildContext context, String id) async {
    final s = state;
    final t = s.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('ui.variant.deleteConfirm', {'name': s.scenario.variantName(id)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ui.variant.delete'))),
        ],
      ),
    );
    if (ok == true) s.deleteVariant(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final p = s.problem;
    if (p == null) return const SizedBox.shrink();
    final variants = s.scenario.variants;
    final current = variants.any((v) => v['id'] == p.variant) ? p.variant : null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldLabel(t('ui.variant.label'), help: t('ui.variant.help')),
              DropdownButtonFormField<String?>(
                key: ValueKey('variant-${p.name}-$current-${variants.length}'),
                initialValue: current,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: null, child: Text(t('ui.variant.base'))),
                  for (final v in variants)
                    DropdownMenuItem(value: v['id'] as String, child: Text(s.scenario.variantName(v['id'] as String))),
                  DropdownMenuItem(value: _newVariant, child: Text(t('ui.variant.new'))),
                ],
                onChanged: (v) => v == _newVariant ? _create(context) : s.chooseVariant(v),
              ),
            ],
          ),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: MenuAnchor(
              builder: (context, m, _) => IconButton(
                tooltip: t('ui.variant.more'),
                icon: const Icon(Icons.more_horiz, size: 20),
                onPressed: () => m.isOpen ? m.close() : m.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  onPressed: () async {
                    final name = await _askName(context, t('ui.variant.rename'), s.scenario.variantName(current));
                    if (name != null) s.renameVariant(current, name);
                  },
                  child: Text(t('ui.variant.rename')),
                ),
                MenuItemButton(onPressed: () => _delete(context, current), child: Text(t('ui.variant.delete'))),
              ],
            ),
          ),
      ],
    );
  }
}

/// in the node and edge mask: the values shown are those of the data variant of the problem
class VariantNote extends StatelessWidget {
  final AppState state;
  final String variant;
  const VariantNote({super.key, required this.state, required this.variant});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(Icons.layers_outlined, size: 14, color: Ui.accentDark),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            state.strings('ui.variant.note', {'name': state.scenario.variantName(variant)}),
            style: const TextStyle(fontSize: 12, color: Ui.accentDark),
          ),
        ),
      ],
    ),
  );
}
