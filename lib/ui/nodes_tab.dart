/// Nodes: list for display only, editing in the mask below.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../backend/backend.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';
import 'theme.dart';
import 'widgets.dart';

class NodesTab extends StatelessWidget {
  final AppState state;
  const NodesTab({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final nodes = s.scenario.nodes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(t('ui.tab.nodes'), style: Ui.title),
            Text(
              '${t('ui.nodes.count', {'n': nodes.length})} · ${t('ui.nodes.hint')}',
              style: const TextStyle(fontSize: 13, color: Ui.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(t('ui.node.add')),
              onPressed: () {
                // the new node starts at the selected one - its position is set on the map
                s.addNode(s.node?.position ?? (nodes.isEmpty ? const LatLng(52.52, 13.40) : nodes.first.position));
                s.setPlacing(true);
              },
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: t('ui.node.delete'),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero),
                onPressed: s.node == null ? null : s.deleteNode,
                child: const Icon(Icons.delete_outline, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: Ui.gap),
        _NodeFilter(state: s),
        const SizedBox(height: 8),
        Section(
          padding: EdgeInsets.zero,
          child: _NodeTable(state: s),
        ),
        const SizedBox(height: 16),
        if (s.node != null)
          _NodeMask(key: ValueKey('${identityHashCode(s.node!.json)}|${t.language}'), state: s, node: s.node!)
        else
          Text(t('ui.node.none'), style: const TextStyle(color: Ui.textSecondary)),
      ],
    );
  }
}

class _NodeTable extends StatelessWidget {
  final AppState state;
  const _NodeTable({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final spec = s.spec;
    final params = s.problem?.parameters ?? const <String, dynamic>{};
    // one column per role of the problem with its main value (tpp: supply, demand); without problem all roles
    // all nodes: the main value of every role; one role: the fields of that role
    final filter = s.nodeFilter;
    final roleColumns = [
      for (final r in spec?.roles ?? const <RoleSpec>[])
        if (filter == null)
          (role: spec!.nodeRole(r, params), field: r.mainField, label: t(r.mainField?.label ?? r.label))
        else if (spec!.nodeRole(r, params) == filter)
          for (final f in r.nodeFields.where((f) => f.isVisible(params) && f.kind != FieldKind.boolean))
            (role: filter, field: f as FieldSpec?, label: t(f.label)),
    ];
    String roleValue(Node n, ({String role, FieldSpec? field, String label}) c) {
      if (!n.roles.contains(c.role)) return '';
      final f = c.field;
      if (f == null) return '✓'; // role without a main value
      final v = n[f.key] ?? f.defaultValue;
      return v is num ? t.number(v) : (v == 'M' ? '∞' : '');
    }

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
    const head = Ui.textSecondary;
    return Column(
      children: [
        row([
          cell(t('ui.col.id'), flex: 1, bold: true, color: head),
          cell(t('ui.col.name'), flex: 3, bold: true, color: head),
          if (roleColumns.isEmpty) cell(t('ui.col.roles'), bold: true, color: head),
          for (final c in roleColumns) cell(c.label, right: true, bold: true, color: head),
          cell(t('ui.col.coords'), flex: 3, bold: true, color: head),
        ], background: Ui.surfaceAlt),
        for (final n in s.filteredNodes)
          // nodes without a role in the problem are pale - their roles are for other problems of the scenario
          if (s.isRelevant(n) case final relevant)
            Semantics(
              button: true,
              selected: n.id == s.selectedNode,
              child: row(
                [
                  cell(n.id, flex: 1, bold: true, color: relevant ? Ui.text : Ui.textSecondary),
                  cell(n.name, flex: 3, color: relevant ? Ui.text : Ui.textSecondary),
                  if (roleColumns.isEmpty) cell(n.roles.map((r) => t('role.$r')).join(', '), color: Ui.textMuted),
                  for (final c in roleColumns) cell(roleValue(n, c), right: true),
                  cell(
                    '${t.fixed(n.position.latitude, 4)} / ${t.fixed(n.position.longitude, 4)}',
                    flex: 3,
                    color: Ui.textSecondary,
                  ),
                ],
                selected: n.id == s.selectedNode,
                background: n.id == s.selectedNode ? Ui.accentLight : null,
                onTap: () => s.selectNode(n.id),
              ),
            ),
      ],
    );
  }
}

class _NodeMask extends StatelessWidget {
  final AppState state;
  final Node node;
  const _NodeMask({super.key, required this.state, required this.node});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final n = node;
    final spec = s.spec;
    final params = s.problem?.parameters ?? const <String, dynamic>{};
    final moduleFields = spec?.nodeFieldsFor(n.roles, params) ?? const [];
    final idTaken = <String>{
      for (final o in s.scenario.nodes)
        if (!identical(o.json, n.json)) o.id,
    };

    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text('${n.id} · ${n.name}', style: Ui.title),
              Text(t('ui.node.detail'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          FieldGrid(
            children: [
              _IdField(node: n, taken: idTaken, state: s),
              TextValueField(label: t('ui.col.name'), value: n.name, onChanged: (v) => s.edit(() => n.name = v)),
            ],
          ),
          const SizedBox(height: 14),
          _RoleChips(state: s, node: n),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextValueField(
                  label: t('ui.node.address'),
                  value: n.address ?? '',
                  onChanged: (v) => s.edit(() => n.address = v),
                ),
              ),
              const SizedBox(width: 8),
              _GeocodeButton(state: s, node: n),
            ],
          ),
          const SizedBox(height: 14),
          FieldGrid(
            columns: 3,
            children: [
              NumberField(
                label: t('ui.node.lat'),
                value: n.position.latitude,
                strings: t,
                check: (v) =>
                    v != null && v.abs() > 90 ? Message('error.min', {'label': 'ui.node.lat', 'min': -90}) : null,
                onChanged: (v) =>
                    v == null ? null : s.edit(() => n.position = LatLng(v.toDouble(), n.position.longitude)),
              ),
              NumberField(
                label: t('ui.node.lon'),
                value: n.position.longitude,
                strings: t,
                check: (v) =>
                    v != null && v.abs() > 180 ? Message('error.min', {'label': 'ui.node.lon', 'min': -180}) : null,
                onChanged: (v) =>
                    v == null ? null : s.edit(() => n.position = LatLng(n.position.latitude, v.toDouble())),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel(' '),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: s.placing
                          ? OutlinedButton.styleFrom(
                              backgroundColor: Ui.accentLight,
                              side: const BorderSide(color: Ui.accent),
                            )
                          : null,
                      icon: const Icon(Icons.ads_click, size: 16),
                      label: Text(t('ui.node.place'), overflow: TextOverflow.ellipsis),
                      onPressed: () => s.setPlacing(!s.placing),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (spec != null && moduleFields.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              t('ui.node.fieldsFor', {'type': spec.label}),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.textMuted),
            ),
            const SizedBox(height: 10),
            FieldGrid(
              children: [
                for (final f in moduleFields)
                  SpecField(
                    spec: f,
                    value: n[f.key] ?? f.defaultValue,
                    strings: t,
                    onChanged: (v) => s.edit(() => n[f.key] = v),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          InkWell(
            onTap: () => s.edit(() => n.active = !n.active),
            child: Row(
              children: [
                Checkbox(value: n.active, onChanged: (v) => s.edit(() => n.active = v ?? true)),
                Flexible(child: Text(t('ui.node.active'), style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ID of the node - unique, renamed in the edges too
class _IdField extends StatelessWidget {
  final Node node;
  final Set<String> taken;
  final AppState state;
  const _IdField({required this.node, required this.taken, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.strings;
    return _IdInput(
      label: t('ui.col.id'),
      value: node.id,
      validate: (v) => v.trim().isEmpty
          ? t('error.required', {'label': 'ui.col.id'})
          : taken.contains(v.trim())
          ? t('ui.node.idExists', {'id': v.trim()})
          : null,
      onCommit: (v) => state.edit(() {
        state.scenario.renameNode(node.id, v);
        state.selectedNode = v;
      }),
    );
  }
}

class _IdInput extends StatefulWidget {
  final String label;
  final String value;
  final String? Function(String) validate;
  final ValueChanged<String> onCommit;
  const _IdInput({required this.label, required this.value, required this.validate, required this.onCommit});

  @override
  State<_IdInput> createState() => _IdInputState();
}

class _IdInputState extends State<_IdInput> {
  late final _c = TextEditingController(text: widget.value);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      TextField(
        controller: _c,
        decoration: InputDecoration(errorText: _error),
        onChanged: (v) => setState(() => _error = widget.validate(v)),
        // the id changes only on enter or leaving the field - the selection depends on it
        onSubmitted: _commit,
        onTapOutside: (_) => _commit(_c.text),
      ),
    ],
  );

  void _commit(String v) {
    final id = v.trim();
    if (id == widget.value || widget.validate(id) != null) return;
    widget.onCommit(id);
  }
}

/// looks up the coordinates of the address - one hit is taken, several are offered for choice
class _GeocodeButton extends StatefulWidget {
  final AppState state;
  final Node node;
  const _GeocodeButton({required this.state, required this.node});

  @override
  State<_GeocodeButton> createState() => _GeocodeButtonState();
}

class _GeocodeButtonState extends State<_GeocodeButton> {
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _lookUp() async {
    final s = widget.state;
    final t = s.strings;
    final n = widget.node;
    final address = (n.address ?? '').trim();
    if (address.isEmpty) {
      _snack(t('ui.geo.noAddress'));
      return;
    }
    setState(() => _busy = true);
    List<GeoHit> hits;
    try {
      hits = await s.geocode(address, exceptNode: n.id);
    } catch (e) {
      if (mounted) _snack('${t('ui.status.error')}: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (hits.isEmpty) {
      _snack(t('ui.geo.none', {'address': address}));
      return;
    }
    final hit = hits.length == 1 ? hits.first : await _choose(address, hits);
    if (hit == null || !mounted) return;
    s.edit(() => n.position = hit.position);
    _snack(t('ui.geo.set', {'place': hit.label}));
  }

  Future<GeoHit?> _choose(String address, List<GeoHit> hits) {
    final t = widget.state.strings;
    return showDialog<GeoHit>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(t('ui.geo.choose', {'address': address})),
        children: [
          for (final h in hits)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, h),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.label),
                  Text(
                    '${t.fixed(h.position.latitude, 5)} / ${t.fixed(h.position.longitude, 5)}',
                    style: const TextStyle(fontSize: 12, color: Ui.textSecondary, fontFeatures: Ui.tabular),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(c), child: Text(t('ui.cancel'))),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: OutlinedButton.icon(
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.travel_explore, size: 16),
      label: Text(widget.state.strings('ui.node.geocode')),
      onPressed: _busy ? null : _lookUp,
    ),
  );
}

/// Roles of the node: those of the problem as chips, the others (for other problems of the scenario) on demand.
class _RoleChips extends StatefulWidget {
  final AppState state;
  final Node node;
  const _RoleChips({required this.state, required this.node});

  @override
  State<_RoleChips> createState() => _RoleChipsState();
}

class _RoleChipsState extends State<_RoleChips> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = s.strings;
    final n = widget.node;
    final problemRoles = s.problemRoles;
    final shown = _all ? nodeRoles : problemRoles;
    final others = [
      for (final r in nodeRoles)
        if (n.roles.contains(r) && !problemRoles.contains(r)) r,
    ];
    final hidden = problemRoles.length < nodeRoles.length;

    Widget chip(String r) {
      final on = n.roles.contains(r);
      return FilterChip(
        label: Text(t('role.$r')),
        selected: on,
        labelStyle: TextStyle(
          color: on ? Ui.accentDark : Ui.textMuted,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(color: on ? Ui.accent : Ui.inputBorder),
        onSelected: (v) => s.edit(() => n.roles = v ? [...n.roles, r] : (n.roles..remove(r))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t('ui.col.roles')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final r in shown) chip(r),
            if (hidden)
              TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(t(_all ? 'ui.roles.problem' : 'ui.roles.all')),
              ),
          ],
        ),
        if (!_all && others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('ui.roles.others', {'roles': others.map((r) => t('role.$r')).join(', ')}), style: Ui.small),
          ),
      ],
    );
  }
}

/// Filter of the node list: all nodes, the nodes of one role of the problem, the nodes without a role in it.
class _NodeFilter extends StatelessWidget {
  final AppState state;
  const _NodeFilter({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final problemRoles = s.spec == null ? const <String>[] : s.problemRoles;
    final options = <(String?, String)>[
      (null, t('ui.filter.all')),
      for (final r in problemRoles) (r, t('role.$r.plural')),
      if (problemRoles.isNotEmpty && s.nodesOf('').isNotEmpty) ('', t('ui.filter.others')),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (f, label) in options)
          ChoiceChip(
            label: Text('$label  ${s.nodesOf(f).length}'),
            selected: s.nodeFilter == f,
            labelStyle: TextStyle(
              color: s.nodeFilter == f ? Ui.accentDark : Ui.textMuted,
              fontWeight: s.nodeFilter == f ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: Ui.tabular,
            ),
            side: BorderSide(color: s.nodeFilter == f ? Ui.accent : Ui.inputBorder),
            onSelected: (_) => s.setNodeFilter(f),
          ),
      ],
    );
  }
}
