/// Nodes: list for display only, editing in the mask below.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../backend/backend.dart';
import 'messages.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';
import 'solution_tab.dart' show PartChooser;
import '../model/table_io.dart';
import 'table_dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class NodesTab extends StatelessWidget {
  final AppState state;
  const NodesTab({super.key, required this.state});

  static final _selectedRow = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final nodes = s.scenario.nodes;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(t('ui.tab.nodes'), style: Ui.title),
                  Text(
                    '${t('ui.nodes.count', {'n': nodes.length})} · ${t('ui.nodes.hint')}',
                    style: const TextStyle(fontSize: 13, color: Ui.textSecondary),
                  ),
                ],
              ),
            ),
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
                onPressed: s.node == null ? null : () => _deleteNode(context, s),
                child: const Icon(Icons.delete_outline, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _NodeFilter(state: s)),
            const SizedBox(width: 6),
            // the list as table for Excel and back, the coordinates of the addresses
            MenuAnchor(
              builder: (context, m, _) => Tooltip(
                message: t('ui.table.menu'),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero),
                  onPressed: () => m.isOpen ? m.close() : m.open(),
                  child: const Icon(Icons.table_view_outlined, size: 18),
                ),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
                  onPressed: nodes.isEmpty ? null : () => copyText(context, s, copyTable(s, TableKind.nodes)),
                  child: Text(t('ui.copy.nodes')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.content_paste, size: 18),
                  onPressed: () => showPasteDialog(context, s, TableKind.nodes),
                  child: Text(t('ui.import.nodes')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.travel_explore, size: 18),
                  onPressed: nodes.isEmpty ? null : () => locateAll(context, s),
                  child: Text('${t('ui.geo.allTitle')} …'),
                ),
              ],
            ),
          ],
        ),
        // multi-commodity: the values of one commodity (supply, demand, capacity factor)
        if (s.spec?.usesCommodities == true && s.solutionParts.isNotEmpty) ...[
          const SizedBox(height: 8),
          PartChooser(state: s),
        ],
      ],
    );
    return ListAndMask(
      header: header,
      list: Section(
        padding: EdgeInsets.zero,
        child: _NodeTable(state: s, selectedKey: _selectedRow),
      ),
      mask: s.node != null
          ? _NodeMask(key: ValueKey('${identityHashCode(s.node!.json)}|${t.language}'), state: s, node: s.node!)
          : Text(t('ui.node.none'), style: const TextStyle(color: Ui.textSecondary)),
      selected: s.selectedNode,
      selectedKey: _selectedRow,
      ratio: s.listRatio,
      onRatio: s.setListRatio,
      onRatioEnd: (v) => s.setListRatio(v, save: true),
      onRatioReset: () => s.setListRatio(AppState.defaultListRatio, save: true),
      semanticLabel: t('ui.split.list'),
    );
  }
}

/// deletes the selected node - asks first if it is used elsewhere (edges, depot, parameters of problems)
Future<void> _deleteNode(BuildContext context, AppState s) async {
  final n = s.node;
  if (n == null) return;
  final uses = s.scenario.usages(n.id);
  if (uses.isNotEmpty) {
    final t = s.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('ui.node.deleteUsed', {'node': n.name})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, args) in uses) Text('• ${t(key, args)}'),
            const SizedBox(height: 12),
            Text(t('ui.node.deleteRefs'), style: Ui.small),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ui.node.delete'))),
        ],
      ),
    );
    if (ok != true) return;
  }
  s.deleteNode();
}

/// short labels of the values per commodity if one commodity is shown
const _perCommodity = {
  'supplies': 'field.supply',
  'demands': 'field.demand',
  'capacityFactors': 'field.capacityFactor',
};

class _NodeTable extends StatelessWidget {
  final AppState state;
  final GlobalKey selectedKey;
  const _NodeTable({required this.state, required this.selectedKey});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final spec = s.spec;
    final params = s.problem?.parameters ?? const <String, dynamic>{};
    // one column per role of the problem with its main value (tpp: supply, demand); without problem all roles
    // all nodes: the main value of every role; one role: the fields of that role
    final filter = s.nodeFilter;
    final part = spec?.usesCommodities == true ? s.solutionPart : null;
    final roleColumns = [
      for (final r in spec?.activeRoles(params) ?? const <RoleSpec>[])
        if (filter == null)
          (role: spec!.nodeRole(r, params), field: r.mainField, label: t(r.mainField?.label ?? r.label))
        else if (spec!.nodeRole(r, params) == filter)
          for (final f in r.nodeFields.where((f) => f.isVisible(params) && f.kind != FieldKind.boolean))
            (role: filter, field: f as FieldSpec?, label: t(f.label)),
      // all nodes: the time windows of all roles in one column - main value of none of them
      if (filter == null &&
          spec != null &&
          spec
              .activeRoles(params)
              .any(
                (r) =>
                    r.mainField?.kind != FieldKind.timeWindow &&
                    r.nodeFields.any((f) => f.kind == FieldKind.timeWindow && f.isVisible(params)),
              ))
        (role: '', field: null, label: t('ui.col.timeWindow')),
    ];
    String roleValue(Node n, ({String role, FieldSpec? field, String label}) c) {
      // the time window of any role of the node - not the main value of a role, it has its own column (depot)
      if (c.role.isEmpty) {
        final mains = [for (final r in spec!.roles) r.mainField];
        return s
                .nodeData(n)
                .where((e) => e.$1.kind == FieldKind.timeWindow && !mains.any((m) => identical(m, e.$1)))
                .map((e) => e.$2)
                .firstOrNull ??
            '';
      }
      if (!n.roles.contains(c.role)) return '';
      final f = c.field;
      if (f == null) return '✓'; // role without a main value
      if (f.computed) return s.nodeFieldText(n, f) ?? '';
      final v = n[f.key] ?? f.defaultValue;
      if (f.kind == FieldKind.commodities && part != null) {
        // one commodity - empty: 0 (supply, demand) or 1 (capacity factor)
        final x = (v as Map?)?[part] as num?;
        return x == null ? '' : t.number(x);
      }
      // time window: times of the day
      if (f.kind == FieldKind.timeWindow && v is List) {
        return '${s.clock.format(v[0] as num?)} – ${s.clock.format(v[1] as num?)}';
      }
      if (f.kind == FieldKind.node) return s.nodeFieldText(n, f) ?? '';
      return s.fieldText(v) ?? '';
    }

    // time windows: wider - "08:00 – 12:00"
    bool wide(({String role, FieldSpec? field, String label}) c) =>
        c.role.isEmpty || c.field?.kind == FieldKind.timeWindow;
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
          cell(t('ui.col.name'), flex: 4, bold: true, color: head),
          if (roleColumns.isEmpty) cell(t('ui.col.roles'), bold: true, color: head),
          for (final c in roleColumns)
            cell(
              // one commodity (named in the chooser): the short label - supply instead of supply per commodity
              c.field?.kind == FieldKind.commodities && part != null
                  ? t(_perCommodity[c.field!.key] ?? c.label)
                  // short: without the explanation in brackets
                  : c.label.replaceAll(RegExp(r'\s*\(.*\)'), ''),
              flex: wide(c) ? 3 : 2,
              right: true,
              bold: true,
              color: head,
            ),
          cell(t('ui.col.coords'), flex: 3, bold: true, color: head),
        ], background: Ui.surfaceAlt),
        for (final n in s.filteredNodes)
          // nodes without a role in the problem are pale - their roles are for other problems of the scenario
          if (s.isRelevant(n) case final relevant)
            Semantics(
              key: n.id == s.selectedNode ? selectedKey : null, // the list scrolls to the selected node
              button: true,
              selected: n.id == s.selectedNode,
              child: row(
                [
                  // the name - the ID is only a key (edges, files), it is in the mask
                  cell(n.name, flex: 4, color: relevant ? Ui.text : Ui.textSecondary),
                  if (roleColumns.isEmpty) cell(n.roles.map((r) => t('role.$r')).join(', '), color: Ui.textMuted),
                  for (final c in roleColumns) cell(roleValue(n, c), flex: wide(c) ? 3 : 2, right: true),
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

  static final _geocode = GlobalKey<_GeocodeButtonState>();

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
              Text(n.name, style: Ui.title),
              Text(t('ui.node.detail'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          // the name; the ID small beside it - given automatically, a key for edges, files and imports
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextValueField(
                  label: t('ui.col.name'),
                  value: n.name,
                  onChanged: (v) => s.edit(() => n.name = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IdField(node: n, taken: idTaken, state: s),
              ),
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
                  // a new node not yet set on the map: its coordinates from the address at once
                  onCommit: (v) {
                    if (s.placing && v.trim().isNotEmpty) _geocode.currentState?.lookUp(placed: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              _GeocodeButton(key: _geocode, state: s, node: n),
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
                  if (f.computed)
                    // computed (delivered amount): shown with where it comes from
                    TextValueField(
                      // built again when the amounts change
                      key: ValueKey('${f.key}|${n.id}|${s.nodeFieldText(n, f)}'),
                      label: t(f.label),
                      value: [
                        s.nodeFieldText(n, f) ?? '0',
                        for (final (p, q) in s.deliveries(n)) '${p.name} ${t.number(q)}',
                      ].join(' · '),
                      readOnly: true,
                      onChanged: (_) {},
                    )
                  else
                    SpecField(
                      scenario: s.scenario,
                      onEditRecords: () => s.setTab(DataTab.parameters),
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
        // the id changes only on enter or leaving the field - the selection depends on it; enter: the next field
        textInputAction: TextInputAction.next,
        onEditingComplete: () {},
        onSubmitted: (v) {
          _commit(v);
          focusNextField(context);
        },
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
  const _GeocodeButton({super.key, required this.state, required this.node});

  @override
  State<_GeocodeButton> createState() => _GeocodeButtonState();
}

class _GeocodeButtonState extends State<_GeocodeButton> {
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  /// placed: the node gets its position from the address - no tap into the map any more
  Future<void> lookUp({bool placed = false}) async {
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
      if (mounted) await showError(context, t, '$e');
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
    if (placed) s.setPlacing(false);
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
      onPressed: _busy ? null : lookUp,
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
    // a network flow: also transshipment nodes - one of these roles per node
    final problemRoles = s.assignableRoles;
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
        // one role per problem: a role of the problem replaces its other roles - roles of other problems stay
        onSelected: (v) => s.edit(
          () => n.roles = !v
              ? (n.roles..remove(r))
              : [
                  for (final x in n.roles)
                    if (!(problemRoles.contains(r) && problemRoles.contains(x))) x,
                  r,
                ],
        ),
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
      if (s.nodesOf(AppState.transitFilter).isNotEmpty) (AppState.transitFilter, t('role.transit.plural')),
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
